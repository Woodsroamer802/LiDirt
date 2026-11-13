import Foundation
import simd
import Combine

#if canImport(ARKit)
import ARKit
#endif

/// Frame → grid binning. Throttled processing (~10–15 Hz). No HTTP.
@MainActor
final class CapturePipeline: ObservableObject {
    let accumulator: DEMAccumulator
    let cellSizeM: Double
    let minSamplesPerCell: Int
    let processInterval: TimeInterval

    @Published private(set) var isSampling: Bool = false
    @Published private(set) var isPaused: Bool = true
    @Published private(set) var passCount: Int = 0
    @Published private(set) var trackedAreaM2: Double = 0
    @Published private(set) var cellsFilledPercent: Double = 0
    @Published private(set) var meanResidualM: Double = 0
    @Published private(set) var trackingStateDescription: String = "Not started"
    @Published private(set) var thermalWarning: Bool = false
    @Published private(set) var lastPreview: HeightmapResult?
    @Published private(set) var controlPins: [ControlPin] = []
    @Published private(set) var sampleRateHz: Double = 12

    private var lastProcessTime: TimeInterval = 0
    private var lastPreviewTime: TimeInterval = 0
    private var sessionStart: Date?
    private var groundEstimateY: Double?
    private let groundBandM: Double = 2.5

    init(
        cellSizeM: Double = 0.05,
        minSamplesPerCell: Int = DEMBuilder.defaultMinSamplesPerCell,
        processInterval: TimeInterval = 1.0 / 12.0
    ) {
        self.cellSizeM = cellSizeM
        self.minSamplesPerCell = minSamplesPerCell
        self.processInterval = processInterval
        self.accumulator = DEMAccumulator(cellSizeM: cellSizeM)
    }

    func startSession() {
        accumulator.reset()
        passCount = 1
        isPaused = false
        isSampling = true
        sessionStart = Date()
        controlPins = []
        groundEstimateY = nil
        lastPreview = nil
        trackedAreaM2 = 0
        cellsFilledPercent = 0
        meanResidualM = 0
        trackingStateDescription = "Tracking"
    }

    func pause() {
        isPaused = true
        isSampling = false
    }

    func resume() {
        isPaused = false
        isSampling = true
        if passCount == 0 { passCount = 1 }
    }

    /// User confirms completing a walking pass (increments when starting another sweep).
    func beginNextPass() {
        passCount += 1
        resume()
    }

    func finish() -> (HeightmapResult?, QualityMetrics, TimeInterval) {
        isPaused = true
        isSampling = false
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
            passCount: max(passCount, 1),
            minSamples: minSamplesPerCell
        )
        updateLiveMetrics(cells: cells, heightmap: heightmap, metrics: metrics)
        return (heightmap, metrics, duration)
    }

    func markControlPin(label: String? = nil, at world: SIMD3<Float>) {
        let pin = ControlPin(
            label: label ?? "Pin \(controlPins.count + 1)",
            x: Double(world.x),
            y: Double(world.y),
            z: Double(world.z)
        )
        controlPins.append(pin)
    }

    func noteTrackingState(_ description: String, samplingAllowed: Bool) {
        trackingStateDescription = description
        if !samplingAllowed && isSampling {
            // Auto-pause sampling until tracking recovers; keep session alive.
            isSampling = false
        } else if samplingAllowed && !isPaused {
            isSampling = true
        }
    }

    func noteThermalPressure(_ elevated: Bool) {
        thermalWarning = elevated
        sampleRateHz = elevated ? 6 : 12
    }

    /// Ingest mesh vertices in session world coordinates (ARKit +Y up).
    func ingestVertices(_ vertices: [SIMD3<Float>], timestamp: TimeInterval) {
        guard isSampling, !isPaused else { return }
        let interval = 1.0 / sampleRateHz
        guard timestamp - lastProcessTime >= interval else { return }
        lastProcessTime = timestamp

        updateGroundEstimate(from: vertices)
        let filtered = filterGroundOriented(vertices)
        accumulator.addSamples(filtered)

        if timestamp - lastPreviewTime >= 2.0 {
            lastPreviewTime = timestamp
            refreshPreviewMetrics()
        }
    }

    /// Unit-test injection without ARKit (does not bypass device gate in UI).
    func ingestTestPoints(_ points: [SIMD3<Float>]) {
        guard isSampling else { return }
        updateGroundEstimate(from: points)
        accumulator.addSamples(filterGroundOriented(points))
        refreshPreviewMetrics()
    }

    func forceStartSamplingForTests() {
        isPaused = false
        isSampling = true
        if passCount == 0 { passCount = 1 }
        if sessionStart == nil { sessionStart = Date() }
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
            passCount: max(passCount, 1),
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
        cellsFilledPercent = metrics.coverageRatio * 100
        if let heightmap {
            trackedAreaM2 = Double(heightmap.width * heightmap.height) * cellSizeM * cellSizeM * metrics.coverageRatio
        } else {
            trackedAreaM2 = Double(cells.count) * cellSizeM * cellSizeM
        }
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
