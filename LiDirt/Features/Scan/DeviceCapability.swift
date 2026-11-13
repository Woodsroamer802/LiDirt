import Foundation
import UIKit
import ARKit

enum DeviceCapability {
    /// True only when the hardware can run scene-reconstruction mesh (LiDAR Pro class).
    static var supportsLiDARSceneReconstruction: Bool {
        #if targetEnvironment(simulator)
        // Simulator never has LiDAR; gate remains honest — no fake scan path.
        return false
        #else
        return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        #endif
    }

    static var supportsLiDARDepth: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
            || ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
        #endif
    }

    static var canStartScan: Bool {
        supportsLiDARSceneReconstruction
    }

    static var deviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    static var osVersionString: String {
        UIDevice.current.systemVersion
    }
}
