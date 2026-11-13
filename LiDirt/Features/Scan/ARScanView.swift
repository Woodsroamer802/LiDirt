import SwiftUI
import RealityKit
import ARKit
import AVFoundation

/// RealityKit `ARView` wrapper. Real ARKit path for device; simulator shows placeholder (no fake DEM).
struct ARScanView: UIViewRepresentable {
    @ObservedObject var pipeline: CapturePipeline
    var onCameraPermissionDenied: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(pipeline: pipeline, onCameraPermissionDenied: onCameraPermissionDenied)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        context.coordinator.attach(to: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.pipeline = pipeline
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        var pipeline: CapturePipeline
        var onCameraPermissionDenied: (() -> Void)?
        private weak var arView: ARView?
        private var isRunning = false

        init(pipeline: CapturePipeline, onCameraPermissionDenied: (() -> Void)?) {
            self.pipeline = pipeline
            self.onCameraPermissionDenied = onCameraPermissionDenied
        }

        func attach(to arView: ARView) {
            self.arView = arView
            #if targetEnvironment(simulator)
            // Simulator: do not start AR session or invent depth. Capture is blocked upstream.
            arView.environment.background = .color(.darkGray)
            #else
            guard DeviceCapability.supportsLiDARSceneReconstruction else { return }
            startSession(on: arView)
            #endif
        }

        func teardown() {
            arView?.session.pause()
            arView?.session.delegate = nil
            isRunning = false
        }

        #if !targetEnvironment(simulator)
        private func startSession(on arView: ARView) {
            guard !isRunning else { return }
            let config = ARWorldTrackingConfiguration()
            config.sceneReconstruction = .mesh
            config.environmentTexturing = .none
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                config.frameSemantics.insert(.sceneDepth)
            }

            arView.session.delegate = self
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            isRunning = true
            arView.debugOptions.insert(.showSceneUnderstanding)
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let state = frame.camera.trackingState
            let allowed: Bool
            let description: String
            switch state {
            case .normal:
                allowed = true
                description = "Tracking"
            case .limited(let reason):
                allowed = false
                description = limitedReasonText(reason)
            case .notAvailable:
                allowed = false
                description = "Tracking unavailable"
            @unknown default:
                allowed = false
                description = "Tracking unknown"
            }
            Task { @MainActor in
                pipeline.noteTrackingState(description, samplingAllowed: allowed)
            }

            guard allowed else { return }
            ingestMeshAnchors(session: session, timestamp: frame.timestamp)
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            let ns = error as NSError
            if ns.domain == AVFoundationErrorDomain
                || ns.localizedDescription.lowercased().contains("camera") {
                Task { @MainActor in
                    onCameraPermissionDenied?()
                }
            }
            Task { @MainActor in
                pipeline.noteTrackingState("Session error", samplingAllowed: false)
            }
        }

        func sessionWasInterrupted(_ session: ARSession) {
            Task { @MainActor in
                pipeline.pause()
                pipeline.noteTrackingState("Interrupted", samplingAllowed: false)
            }
        }

        private func ingestMeshAnchors(session: ARSession, timestamp: TimeInterval) {
            let meshAnchors = session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
            var points: [SIMD3<Float>] = []
            points.reserveCapacity(meshAnchors.count * 256)

            for anchor in meshAnchors {
                let geometry = anchor.geometry
                let source = geometry.vertices
                let transform = anchor.transform
                let count = source.count
                let strideCount = max(1, count / 400)
                for i in Swift.stride(from: 0, to: count, by: strideCount) {
                    let local = Self.vertex(source, at: i)
                    let world = transform * SIMD4<Float>(local.x, local.y, local.z, 1)
                    points.append(SIMD3<Float>(world.x, world.y, world.z))
                }
            }

            guard !points.isEmpty else { return }
            Task { @MainActor in
                pipeline.ingestVertices(points, timestamp: timestamp)
            }
        }

        private static func vertex(_ source: ARGeometrySource, at index: Int) -> SIMD3<Float> {
            precondition(source.componentsPerVector >= 3)
            let pointer = source.buffer.contents().advanced(by: source.offset + source.stride * index)
            let floats = pointer.bindMemory(to: Float.self, capacity: 3)
            return SIMD3<Float>(floats[0], floats[1], floats[2])
        }

        private func limitedReasonText(_ reason: ARCamera.TrackingState.Reason) -> String {
            switch reason {
            case .initializing: return "Initializing…"
            case .excessiveMotion: return "Move slower / better light"
            case .insufficientFeatures: return "Move slower / better light"
            case .relocalizing: return "Relocalizing…"
            @unknown default: return "Limited tracking"
            }
        }
        #endif
    }
}
