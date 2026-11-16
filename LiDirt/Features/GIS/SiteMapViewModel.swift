import Foundation
import MapKit
import CoreLocation
import Combine

@MainActor
final class SiteMapViewModel: NSObject, ObservableObject {
    @Published var region: MKCoordinateRegion
    @Published var userCoordinate: CLLocationCoordinate2D?
    @Published var showTopo = true
    @Published var showContours = true
    @Published var contourIntervalInches: Double
    @Published var contourPolylines: [ContourMapGeoref.ContourPolyline] = []
    @Published var statusMessage = "Locating…"
    @Published var contourNote: String?

    private let locationManager = CLLocationManager()
    private let heightmap: HeightmapResult?
    private let orientation: ScanOrientationSnapshot
    private var didFitScanRegion = false

    init(
        heightmap: HeightmapResult? = nil,
        orientation: ScanOrientationSnapshot = .unavailable,
        contourIntervalInches: Double = ContourPreview.defaultIntervalInches,
        initialCoordinate: CLLocationCoordinate2D? = nil
    ) {
        self.heightmap = heightmap
        self.orientation = orientation
        self.contourIntervalInches = max(contourIntervalInches, 0.01)

        if let lat = orientation.latitude, let lon = orientation.longitude {
            let origin = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            if let heightmap {
                region = ContourMapGeoref.region(heightmap: heightmap, origin: origin)
                didFitScanRegion = true
            } else {
                region = MKCoordinateRegion(
                    center: origin,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
            }
            userCoordinate = origin
        } else if let initialCoordinate {
            region = MKCoordinateRegion(
                center: initialCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            userCoordinate = initialCoordinate
        } else {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)
            )
        }
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        rebuildContours()
    }

    func onAppear() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        if heightmap == nil {
            statusMessage = "USGS topo — scan a pad to overlay LiDAR contours."
        } else if orientation.latitude == nil {
            statusMessage = "Scan has no GPS fix — showing topo only."
            contourNote = GISDisclaimer.needScanGPS
        } else {
            refreshStatus()
        }
    }

    func onDisappear() {
        locationManager.stopUpdatingLocation()
    }

    func setContourIntervalInches(_ inches: Double) {
        let clamped = max(inches, 0.01)
        guard abs(clamped - contourIntervalInches) > 1e-9 else { return }
        contourIntervalInches = clamped
        rebuildContours()
        refreshStatus()
    }

    func rebuildContours() {
        guard showContours,
              let heightmap,
              let lat = orientation.latitude,
              let lon = orientation.longitude else {
            contourPolylines = []
            if heightmap != nil, orientation.latitude == nil {
                contourNote = GISDisclaimer.needScanGPS
            } else if heightmap == nil {
                contourNote = nil
            } else if !showContours {
                contourNote = nil
            }
            return
        }

        let origin = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        contourPolylines = ContourMapGeoref.polylines(
            heightmap: heightmap,
            origin: origin,
            intervalInches: contourIntervalInches
        )
        if !orientation.frameAlignedToNorth {
            contourNote = "Contours placed with GPS; scan was not north-aligned — orientation is approximate."
        } else {
            contourNote = nil
        }
    }

    func regionDidChange(_ newRegion: MKCoordinateRegion) {
        region = newRegion
    }

    private func refreshStatus() {
        if let heightmap, orientation.latitude != nil {
            let label: String
            if contourIntervalInches < 1 {
                label = String(format: "%.3g in", contourIntervalInches)
            } else {
                label = String(format: "%.2g in", contourIntervalInches)
            }
            statusMessage = "LiDAR contours @ \(label) over USGS topo (\(contourPolylines.count) segments)."
            if !didFitScanRegion, let lat = orientation.latitude, let lon = orientation.longitude {
                region = ContourMapGeoref.region(
                    heightmap: heightmap,
                    origin: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
                didFitScanRegion = true
            }
        } else if heightmap != nil {
            statusMessage = "Scan loaded — need GPS on the scan to place contours."
        } else {
            statusMessage = "USGS topo — scan a pad to overlay LiDAR contours."
        }
    }
}

extension SiteMapViewModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.startUpdatingLocation()
            case .denied, .restricted:
                if heightmap == nil {
                    statusMessage = "Location denied — pan the topo map manually."
                }
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            let coord = location.coordinate
            let firstFix = userCoordinate == nil
            userCoordinate = coord
            if firstFix, heightmap == nil {
                region = MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
            }
            if heightmap == nil {
                statusMessage = String(
                    format: "GPS %.5f, %.5f (±%.0f m) — scan to overlay contours.",
                    coord.latitude,
                    coord.longitude,
                    max(location.horizontalAccuracy, 0)
                )
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if heightmap == nil {
                statusMessage = "GPS error — pan the map manually."
            }
        }
    }
}
