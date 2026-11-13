import Foundation
import simd
import Combine

#if canImport(ARKit)
import ARKit
#endif

/// Manual pass lifecycle — user explicitly begins and ends each pass.
enum PassPhase: Equatable {
    case awaitingBegin
    case countdown(Int)
    case sampling
    case paused
    case passEnded
}

/// Frame → grid binning. Throttled processing (~10–15 Hz). No HTTP.
@MainActor
final class CapturePipeline: ObservableObject {
    let accumulator: DEMAccumulator
    let cellSizeM: Double
    let minSamplesPerCell: Int
    let processInterval: TimeInterval
    let goalSamplesPerCell: Int

    @Published private(set) var passPhase: PassPhase = .awaitingBegin
    @Published private(set) var isSampling: Bool = false
    @Published private(set) var passCount: Int = 0
    @Published private(set) var completedPassCount: Int = 0
    @Published private(set) var trackedAreaM2: Double = 0
    /// Percent of hull cells that met the green coverage goal.
    @Published private(set) var goalMetPercent: Double = 0
    /// Percent of hull cells with any samples (incomplete + goal).
    @Published private(set) var cellsTouchedPercent: Double = 0
    @Published private(set) var meanResidualM: Double = 0
    @Published private(set) var trackingStateDescription: String = "Not started"
    @Published private(set) var thermalWarning: Bool = false
    @Published private(set) var lastPreview: HeightmapResult?
    @Published private(set) var controlPins: [ControlPin] = []
    @Published private(set) var sampleRateHz: Double = 12
    @Published private(set) var orientation: ScanOrientationSnapshot = .unavailable

    /// Applied to ARKit points before binning when north calibration succeeded.
    private(set) var northAlignYawRadians: Double?

    private var lastProcessTime: TimeInterval = 0
    private var lastPreviewTime: TimeInterval = 0
    private var sessionStart: Date?
    private var groundEstimateY: Double?
    private let groundBandM: Double = 2.5
    private var trackingAllowsSampling = true
    private var countdownTask: Task<Void, Never>?

    init(
        cellSizeM: Double = 0.05,
        minSamplesPerCell: Int = DEMBuilder.defaultMinSamplesPerCell,
        goalSamplesPerCell: Int = CoverageGoals.samplesForGoalMet,
        processInterval: TimeInterval = 1.0 / 12.0
    ) {
        self.cellSizeM = cellSizeM
        self.minSamplesPerCell = minSamplesPerCell
        self.goalSamplesPerCell = goalSamplesPerCell
        self.processInterval = processInterval
        self.accumulator = DEMAccumulator(cellSizeM: cellSizeM)
    }

    /// Prepare a new scan session without collecting samples until the user begins a pass.
    func prepareSession() {
        countdownTask?.cancel()
        countdownTask = nil
        accumulator.reset()
        passCount = 1
        completedPassCount = 0
        passPhase = .awaitingBegin
        isSampling = false
        sessionStart = Date()
        controlPins = []
        groundEstimateY = nil
        lastPreview = nil
        trackedAreaM2 = 0
        goalMetPercent = 0
        cellsTouchedPercent = 0
        meanResidualM = 0
        trackingStateDescription = "Ready — begin pass when set"
        northAlignYawRadians = nil
    }

    /// Explicit start: optional 3–2–1 countdown, then sampling for the current pass number.
    /// Call only from `.awaitingBegin` (use `prepareNextPass()` after ending a pass).
    func beginPass(countdownSeconds: Int = 3) {
        guard passPhase == .awaitingBegin else { return }
        if passCount == 0 { passCount = 1 }

        countdownTask?.cancel()
        if countdownSeconds <= 0 {
            enterSampling()
            return
        }
        passPhase = .countdown(countdownSeconds)
        isSampling = false
        countdownTask = Task { [weak self] in
            var remaining = countdownSeconds
            while remaining > 0 {
                await MainActor.run {
                    self?.passPhase = .countdown(remaining)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                remaining -= 1
            }
            await MainActor.run {
                self?.enterSampling()
            }
        }
    }

    /// Cancel a pending countdown and return to awaiting begin (does not end the pass).
    func cancelCountdown() {
        guard isCountdown else { return }
        countdownTask?.cancel()
        countdownTask = nil
        isSampling = false
        passPhase = .awaitingBegin
        trackingStateDescription = "Ready — begin pass when set"
    }

    func endPass() {
        guard passPhase == .sampling || passPhase == .paused else { return }
        countdownTask?.cancel()
        countdownTask = nil
        isSampling = false
        completedPassCount = max(completedPassCount, passCount)
        passPhase = .passEnded
        trackingStateDescription = "Pass \(passCount) ended"
        refreshPreviewMetrics()
    }

    /// After ending a pass, return to awaiting begin for the next pass (does not auto-sample).
    func prepareNextPass() {
        guard passPhase == .passEnded else { return }
        passCount = max(passCount, completedPassCount) + 1
        passPhase = .awaitingBegin
        isSampling = false
        trackingStateDescription = "Ready — begin pass \(passCount)"
    }

    func pause() {
        guard passPhase == .sampling else { return }
        passPhase = .paused
        isSampling = false
    }

    func resume() {
        guard passPhase == .paused else { return }
        passPhase = .sampling
        isSampling = trackingAllowsSampling
    }

    func finish() -> (HeightmapResult?, QualityMetrics, TimeInterval) {
        countdownTask?.cancel()
        countdownTask = nil
        if passPhase == .sampling || passPhase == .paused {
            completedPassCount = max(completedPassCount, passCount)
        }
        isSampling = false
        passPhase = .passEnded
        let duration = Date().timeIntervalSince(sessionStart ?? Date())
        let cells = accumulator.snapshot()
        let heightmap = DEMBuilder.buildHeightmap(
            cells: cells,
            cellSizeM: cellSizeM,
            minSamples: minSamplesPerCell,
            fillOneCellGaps: true
        )
        lastPreview = heightmap
        let metrics = QualityScorer.score(
            cells: cells,
            heightmap: heightmap,
            passCount: max(completedPassCount, passCount > 0 ? 1 : 0),
            minSamples: minSamplesPerCell
        )
        updateLiveMetrics(cells: cells, heightmap: heightmap, metrics: metrics)
        return (heightmap, metrics, duration)
    }

    func applyOrientation(_ snapshot: ScanOrientationSnapshot) {
        orientation = snapshot
        if let yaw = snapshot.northAlignYawRadians, snapshot.frameAlignedToNorth {
            northAlignYawRadians = yaw
        }
    }

    func markControlPin(label: String? = nil, at world: SIMD3<Float>) {
        let aligned = alignPoint(world)
        let pin = ControlPin(
            label: label ?? "Pin \(controlPins.count + 1)",
            x: Double(aligned.x),
            y: Double(aligned.y),
            z: Double(aligned.z)
        )
        controlPins.append(pin)
    }

    func noteTrackingState(_ description: String, samplingAllowed: Bool) {
        trackingAllowsSampling = samplingAllowed
        if passPhase == .awaitingBegin || passPhase == .passEnded || isCountdown {
            trackingStateDescription = description
            return
        }
        trackingStateDescription = description
        if passPhase == .sampling {
            isSampling = samplingAllowed
        } else if passPhase == .paused {
            isSampling = false
        }
    }

    func noteThermalPressure(_ elevated: Bool) {
        thermalWarning = elevated
        sampleRateHz = elevated ? 6 : 12
    }

    /// Ingest mesh vertices in session world coordinates (ARKit +Y up).
    func ingestVertices(_ vertices: [SIMD3<Float>], timestamp: TimeInterval) {
        guard isSampling, passPhase == .sampling else { return }
        let interval = 1.0 / sampleRateHz
        guard timestamp - lastProcessTime >= interval else { return }
        lastProcessTime = timestamp

        let aligned = vertices.map { alignPoint($0) }
        updateGroundEstimate(from: aligned)
        let filtered = filterGroundOriented(aligned)
        accumulator.addSamples(filtered)

        if timestamp - lastPreviewTime >= 2.0 {
            lastPreviewTime = timestamp
            refreshPreviewMetrics()
        }
    }

    /// Unit-test injection without ARKit (does not bypass device gate in UI).
    func ingestTestPoints(_ points: [SIMD3<Float>]) {
        guard isSampling, passPhase == .sampling else { return }
        let aligned = points.map { alignPoint($0) }
        updateGroundEstimate(from: aligned)
        accumulator.addSamples(filterGroundOriented(aligned))
        refreshPreviewMetrics()
    }

    func forceStartSamplingForTests() {
        countdownTask?.cancel()
        passCount = max(passCount, 1)
        enterSampling()
        if sessionStart == nil { sessionStart = Date() }
    }

    private var isCountdown: Bool {
        if case .countdown = passPhase { return true }
        return false
    }

    private func enterSampling() {
        passPhase = .sampling
        isSampling = trackingAllowsSampling
        trackingStateDescription = trackingAllowsSampling ? "Tracking — walk now" : trackingStateDescription
    }

    private func alignPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        guard let yaw = northAlignYawRadians else { return point }
        return NorthAlignMath.rotateAroundY(point, yawRadians: yaw)
    }

    private func refreshPreviewMetrics() {
        let cells = accumulator.snapshot()
        let heightmap = DEMBuilder.buildHeightmap(
            cells: cells,
            cellSizeM: cellSizeM,
            minSamples: minSamplesPerCell,
            fillOneCellGaps: false
        )
        lastPreview = heightmap
        let metrics = QualityScorer.score(
            cells: cells,
            heightmap: heightmap,
            passCount: max(completedPassCount, 1),
            minSamples: minSamplesPerCell
        )
        updateLiveMetrics(cells: cells, heightmap: heightmap, metrics: metrics)
    }

    private func updateLiveMetrics(
        cells: [DEMGridKey: DEMCellStats],
        heightmap: HeightmapResult?,
        metrics: QualityMetrics
    ) {
        meanResidualM = metrics.rmsResidualM
        if let heightmap, heightmap.width > 0, heightmap.height > 0 {
            let hull = heightmap.width * heightmap.height
            var goalMet = 0
            var touched = 0
            for count in heightmap.sampleCounts {
                if count > 0 { touched += 1 }
                if count >= goalSamplesPerCell { goalMet += 1 }
            }
            // Also count cells that exist in accumulator but were holes in heightmap (below minSamples).
            for (_, stats) in cells {
                if stats.count > 0 && stats.count < minSamplesPerCell {
                    touched += 1
                }
                if stats.count >= goalSamplesPerCell {
                    // already counted if in heightmap; if not in heightmap width, rare
                }
            }
            goalMetPercent = Double(goalMet) / Double(hull) * 100
            cellsTouchedPercent = Double(min(touched, hull)) / Double(hull) * 100
            trackedAreaM2 = Double(goalMet) * cellSizeM * cellSizeM
        } else {
            let total = max(cells.count, 1)
            let goalMet = cells.values.filter { $0.count >= goalSamplesPerCell }.count
            let touched = cells.values.filter { $0.count > 0 }.count
            goalMetPercent = Double(goalMet) / Double(total) * 100
            cellsTouchedPercent = Double(touched) / Double(total) * 100
            trackedAreaM2 = Double(goalMet) * cellSizeM * cellSizeM
        }
        _ = metrics
    }

    private func updateGroundEstimate(from vertices: [SIMD3<Float>]) {
        guard !vertices.isEmpty else { return }
        let ys = vertices.map { Double($0.y) }.sorted()
        let median = ys[ys.count / 2]
        if let existing = groundEstimateY {
            groundEstimateY = existing * 0.9 + median * 0.1
        } else {
            groundEstimateY = median
        }
    }

    private func filterGroundOriented(_ vertices: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard let ground = groundEstimateY else { return vertices }
        return vertices.filter { abs(Double($0.y) - ground) <= groundBandM }
    }
}
