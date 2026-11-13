import Foundation
import simd
import Combine

@MainActor
final class ScanSessionViewModel: ObservableObject {
    let projectId: UUID
    let scanId: UUID
    let pipeline: CapturePipeline
    let orientationService: ScanOrientationService

    @Published var showCameraDenied = false
    @Published var showFinishConfirm = false
    @Published var completedHeightmap: HeightmapResult?
    @Published var completedMetrics: QualityMetrics?
    @Published var completedOrientation: ScanOrientationSnapshot = .unavailable
    @Published var durationSec: TimeInterval = 0
    @Published var didFinish = false
    @Published var suggestedPasses: Int = 3
    /// Latest AR camera transform from the AR view (device only); used for north calibrate.
    var latestCameraTransform: simd_float4x4?

    init(projectId: UUID, cellSizeM: Double = 0.05) {
        self.projectId = projectId
        self.scanId = UUID()
        self.pipeline = CapturePipeline(cellSizeM: cellSizeM)
        self.orientationService = ScanOrientationService()
    }

    var passLabel: String {
        let current = max(pipeline.passCount, 1)
        return "Pass \(current) of \(suggestedPasses)"
    }

    var areaLabel: String {
        let yd2 = pipeline.trackedAreaM2 * 1.19599
        return String(format: "%.1f m² · %.1f yd²", pipeline.trackedAreaM2, yd2)
    }

    var phaseHint: String {
        switch pipeline.passPhase {
        case .awaitingBegin:
            return "Hold still, then tap Begin pass when ready to walk."
        case .countdown(let n):
            return "Starting in \(n)…"
        case .sampling:
            return "Walk the pad. Green = coverage goal met."
        case .paused:
            return "Paused — Resume to keep collecting this pass."
        case .passEnded:
            return "Pass ended. Start next pass or Finish scan."
        }
    }

    func onAppear() {
        pipeline.prepareSession()
        orientationService.requestAccessAndStart()
    }

    func onDisappear() {
        orientationService.stop()
    }

    func beginPass() {
        orientationService.calibrate(cameraTransform: latestCameraTransform)
        pipeline.applyOrientation(orientationService.snapshot)
        pipeline.beginPass(countdownSeconds: 3)
    }

    func endPass() {
        pipeline.endPass()
    }

    func cancelCountdown() {
        pipeline.cancelCountdown()
    }

    func startNextPass() {
        pipeline.prepareNextPass()
    }

    func pause() {
        pipeline.pause()
    }

    func resume() {
        pipeline.resume()
    }

    func markPin() {
        pipeline.markControlPin(at: SIMD3<Float>(0, Float(pipeline.lastPreview?.bounds.minY ?? 0), 0))
    }

    func finish() {
        orientationService.calibrate(cameraTransform: latestCameraTransform)
        pipeline.applyOrientation(orientationService.snapshot)
        let (heightmap, metrics, duration) = pipeline.finish()
        completedHeightmap = heightmap
        completedMetrics = metrics
        completedOrientation = orientationService.snapshot
        durationSec = duration
        orientationService.stop()
        didFinish = true
    }

    func handleBackground() {
        if pipeline.passPhase == .sampling {
            pipeline.pause()
        }
    }
}
