import Foundation
import CoreLocation
import simd
import Combine

/// Snapshot of phone GPS/compass used to align DEM to north. Approximate — not survey-grade.
struct ScanOrientationSnapshot: Equatable, Sendable {
    var method: String
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracyM: Double?
    var headingDegrees: Double?
    var headingAccuracyDegrees: Double?
    var headingSource: String
    /// Radians: rotate ARKit (x,z) around +Y so +Z ≈ true north when available.
    var northAlignYawRadians: Double?
    var frameAlignedToNorth: Bool
    var disclaimer: String

    static let phoneDisclaimer =
        "Phone GPS and compass orientation is approximate (meters-class GNSS, degrees-class heading noise). Not survey-grade north or absolute elevation."

    static var unavailable: ScanOrientationSnapshot {
        ScanOrientationSnapshot(
            method: "none",
            latitude: nil,
            longitude: nil,
            horizontalAccuracyM: nil,
            headingDegrees: nil,
            headingAccuracyDegrees: nil,
            headingSource: "unavailable",
            northAlignYawRadians: nil,
            frameAlignedToNorth: false,
            disclaimer: phoneDisclaimer
        )
    }
}

/// Pure math helpers for north alignment (unit-testable).
enum NorthAlignMath {
    /// Device forward yaw in ARKit XZ: atan2(forward.x, forward.z), radians.
    static func arkitForwardYaw(cameraTransform: simd_float4x4) -> Double {
        // Camera looks down −Z in local space; world forward is −column2.
        let forward = -SIMD3<Float>(
            cameraTransform.columns.2.x,
            cameraTransform.columns.2.y,
            cameraTransform.columns.2.z
        )
        let flat = SIMD3<Float>(forward.x, 0, forward.z)
        let len = simd_length(flat)
        guard len > 1e-4 else { return 0 }
        let n = flat / len
        return Double(atan2(n.x, n.z))
    }

    /// Yaw that maps compass-forward to +Z-north after rotation around Y.
    /// `compassHeadingDegrees` is Core Location true/magnetic heading (clockwise from north).
    static func northAlignYaw(
        arkitForwardYawRadians: Double,
        compassHeadingDegrees: Double
    ) -> Double {
        let compassRad = compassHeadingDegrees * .pi / 180.0
        // Compass heading is clockwise from north; ARKit yaw is CCW from +Z.
        // Align device-forward with compass bearing, then rotate world so north → +Z.
        return arkitForwardYawRadians + compassRad
    }

    static func rotateAroundY(_ point: SIMD3<Float>, yawRadians: Double) -> SIMD3<Float> {
        let c = Float(cos(yawRadians))
        let s = Float(sin(yawRadians))
        return SIMD3(
            point.x * c - point.z * s,
            point.y,
            point.x * s + point.z * c
        )
    }
}

/// Core Location wrapper for GPS + heading during a scan session.
@MainActor
final class ScanOrientationService: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var lastHeading: CLHeading?
    @Published private(set) var snapshot: ScanOrientationSnapshot = .unavailable
    @Published private(set) var statusMessage: String = "Orientation idle"

    private let manager = CLLocationManager()
    private var pendingCameraTransform: simd_float4x4?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2
        manager.headingFilter = 1
        manager.headingOrientation = .portrait
        authorizationStatus = manager.authorizationStatus
    }

    func requestAccessAndStart() {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            statusMessage = "Requesting location…"
        case .authorizedWhenInUse, .authorizedAlways:
            // Ask for full accuracy when reduced-accuracy mode is on (iOS 14+).
            if #available(iOS 14.0, *), manager.accuracyAuthorization == .reducedAccuracy {
                manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "FullAccuracyPurpose")
            }
            startUpdating()
        case .denied, .restricted:
            statusMessage = "Location/heading denied — DEM stays local frame"
            snapshot = .unavailable
        @unknown default:
            statusMessage = "Location unavailable"
            snapshot = .unavailable
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    /// Call when user begins a pass; optionally pass current AR camera transform for yaw calibration.
    func calibrate(cameraTransform: simd_float4x4?) {
        pendingCameraTransform = cameraTransform
        rebuildSnapshot(cameraTransform: cameraTransform)
    }

    private func startUpdating() {
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
            statusMessage = "Seeking GPS + compass…"
        } else {
            statusMessage = "GPS only — compass unavailable"
            manager.startUpdatingLocation()
        }
    }

    private func rebuildSnapshot(cameraTransform: simd_float4x4?) {
        let location = lastLocation
        let (headingDegrees, headingAccuracy, headingSource) = Self.parseHeading(lastHeading)

        let yaw: Double?
        let method: String
        let status: String
        if let headingDegrees, let cameraTransform {
            let arYaw = NorthAlignMath.arkitForwardYaw(cameraTransform: cameraTransform)
            yaw = NorthAlignMath.northAlignYaw(
                arkitForwardYawRadians: arYaw,
                compassHeadingDegrees: headingDegrees
            )
            method = location == nil ? "phone_compass" : "phone_compass_gps"
            status = "North aligned (phone compass — approximate)"
        } else if location != nil {
            yaw = nil
            method = "phone_gps"
            status = "GPS only — no heading for north align"
        } else if headingDegrees != nil {
            yaw = nil
            method = "phone_compass"
            status = "Heading only — walk start will calibrate"
        } else {
            yaw = nil
            method = "none"
            status = statusMessage
        }

        statusMessage = status

        let horizontalAccuracy: Double?
        if let location, location.horizontalAccuracy >= 0 {
            horizontalAccuracy = location.horizontalAccuracy
        } else {
            horizontalAccuracy = nil
        }

        snapshot = ScanOrientationSnapshot(
            method: method,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            horizontalAccuracyM: horizontalAccuracy,
            headingDegrees: headingDegrees,
            headingAccuracyDegrees: headingAccuracy,
            headingSource: headingSource,
            northAlignYawRadians: yaw,
            frameAlignedToNorth: yaw != nil,
            disclaimer: ScanOrientationSnapshot.phoneDisclaimer
        )
    }

    /// Prefer true north; fall back to magnetic. Invalid Core Location values are negative.
    private static func parseHeading(_ heading: CLHeading?) -> (Double?, Double?, String) {
        guard let heading else {
            return (nil, nil, "unavailable")
        }
        let accuracy = heading.headingAccuracy >= 0 ? heading.headingAccuracy : nil
        if heading.trueHeading >= 0 {
            return (heading.trueHeading, accuracy, "trueHeading")
        }
        if heading.magneticHeading >= 0 {
            return (heading.magneticHeading, accuracy, "magneticHeading")
        }
        return (nil, nil, "unavailable")
    }
}

extension ScanOrientationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                startUpdating()
            case .denied, .restricted:
                statusMessage = "Location/heading denied — DEM stays local frame"
                snapshot = .unavailable
                stop()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            lastLocation = locations.last
            rebuildSnapshot(cameraTransform: pendingCameraTransform)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            lastHeading = newHeading
            rebuildSnapshot(cameraTransform: pendingCameraTransform)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            statusMessage = "Location error — continuing without north align"
        }
    }
}
