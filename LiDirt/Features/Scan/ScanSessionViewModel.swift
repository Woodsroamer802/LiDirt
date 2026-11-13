import Foundation
import simd
import Combine

@MainActor
final class ScanSessionViewModel: ObservableObject {
    let projectId: UUID
    let scanId: UUID
    let pipeline: CapturePipeline

    @Published var showCameraDenied = false
    @Published var showFinishConfirm = false
    @Published var completedHeightmap: HeightmapResult?
    @Published var completedMetrics: QualityMetrics?
    @Published var durationSec: TimeInterval = 0
    @Published var didFinish = false
    @Published var suggestedPasses: Int = 3

    init(projectId: UUID, cellSizeM: Double = 0.05) {
        self.projectId = projectId
        self.scanId = UUID()
        self.pipeline = CapturePipeline(cellSizeM: cellSizeM)
    }

    var passLabel: String {
        "Pass \(pipeline.passCount) of \(suggestedPasses)"
    }

    var areaLabel: String {
        let yd2 = pipeline.trackedAreaM2 * 1.19599
        return String(format: "%.1f m² · %.1f yd²", pipeline.trackedAreaM2, yd2)
    }

    func onAppear() {
        pipeline.startSession()
    }

    func pause() {
        pipeline.pause()
    }

    func resume() {
        pipeline.resume()
    }

    func nextPass() {
        pipeline.beginNextPass()
    }

    func markPin() {
        // Local XYZ only; no GIS snap in this slice. Use origin as placeholder when no hit test.
        pipeline.markControlPin(at: SIMD3<Float>(0, Float(pipeline.lastPreview?.bounds.minY ?? 0), 0))
    }

    func finish() {
        let (heightmap, metrics, duration) = pipeline.finish()
        completedHeightmap = heightmap
        completedMetrics = metrics
        durationSec = duration
        didFinish = true
    }

    func handleBackground() {
        pipeline.pause()
    }
}
