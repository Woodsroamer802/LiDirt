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
    @Published var isFusing = false
    @Published var fuseProgress: String?
    @Published var fusedResult: FusedDEMResult?
    @Published var printError: String?
    @Published var sharePDFURL: URL?

    let projectName: String
    private let locationManager = CLLocationManager()
    private let lidarHeightmap: HeightmapResult?
    private let orientation: ScanOrientationSnapshot
    private let elevationService: USGSElevationService
    private var fuseTask: Task<Void, Never>?
    private var didFitScanRegion = false

    init(
        projectName: String = "Site",
        heightmap: HeightmapResult? = nil,
        orientation: ScanOrientationSnapshot = .unavailable,
        contourIntervalInches: Double = ContourPreview.defaultIntervalInches,
        elevationService: USGSElevationService = USGSElevationService()
    ) {
        self.projectName = projectName
        self.lidarHeightmap = heightmap
        self.orientation = orientation
        self.contourIntervalInches = max(contourIntervalInches, 0.01)
        self.elevationService = elevationService

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
        if lidarHeightmap == nil {
            statusMessage = "USGS topo — scan a pad to fuse LiDAR detail."
        } else if orientation.latitude == nil {
            statusMessage = "Scan has no GPS fix — showing topo only."
            contourNote = GISDisclaimer.needScanGPS
        } else {
            startFuseIfNeeded()
        }
    }

    func onDisappear() {
        locationManager.stopUpdatingLocation()
        fuseTask?.cancel()
    }

    func setContourIntervalInches(_ inches: Double) {
        let clamped = max(inches, 0.01)
        guard abs(clamped - contourIntervalInches) > 1e-9 else { return }
        contourIntervalInches = clamped
        rebuildContours()
        refreshStatus()
    }

    func startFuseIfNeeded() {
        guard fusedResult == nil, !isFusing else {
            rebuildContours()
            refreshStatus()
            return
        }
        guard let lidarHeightmap,
              let lat = orientation.latitude,
              let lon = orientation.longitude else {
            rebuildContours()
            return
        }

        isFusing = true
        fuseProgress = "Fetching USGS 3DEP foundation…"
        statusMessage = fuseProgress ?? "Fusing…"
        let origin = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let service = elevationService
        fuseTask?.cancel()
        fuseTask = Task {
            do {
                let foundation = try await service.fetchFoundationDEM(
                    covering: lidarHeightmap,
                    origin: origin
                )
                if Task.isCancelled { return }
                fuseProgress = "Blending LiDAR into foundation…"
                statusMessage = fuseProgress ?? "Fusing…"
                let fused = FusedDEMBuilder.fuse(foundation: foundation, lidar: lidarHeightmap)
                if Task.isCancelled { return }
                fusedResult = fused
                isFusing = false
                fuseProgress = nil
                contourNote = nil
                rebuildContours()
                refreshStatus()
            } catch {
                if Task.isCancelled { return }
                // Fallback: contours from LiDAR alone with relative elevations.
                isFusing = false
                fuseProgress = nil
                contourNote = "3DEP unavailable (\(error.localizedDescription)). Showing LiDAR-only contours on topo."
                fusedResult = nil
                rebuildContours()
                refreshStatus()
            }
        }
    }

    func rebuildContours() {
        guard showContours,
              let source = contourSourceHeightmap,
              let lat = orientation.latitude,
              let lon = orientation.longitude else {
            contourPolylines = []
            if lidarHeightmap != nil, orientation.latitude == nil {
                contourNote = GISDisclaimer.needScanGPS
            }
            return
        }

        let origin = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        contourPolylines = ContourMapGeoref.polylines(
            heightmap: source,
            origin: origin,
            intervalInches: contourIntervalInches
        )
        if fusedResult == nil, orientation.latitude != nil, !isFusing, contourNote == nil {
            if !orientation.frameAlignedToNorth {
                contourNote = "Contours placed with GPS; scan was not north-aligned — orientation is approximate."
            }
        }
    }

    func regionDidChange(_ newRegion: MKCoordinateRegion) {
        region = newRegion
    }

    var canExportPrint: Bool {
        contourSourceHeightmap != nil && orientation.latitude != nil && orientation.longitude != nil
    }

    func exportPDF(sheet: PrintSheetSize) {
        printError = nil
        sharePDFURL = nil
        guard let source = contourSourceHeightmap,
              let lat = orientation.latitude,
              let lon = orientation.longitude else {
            printError = "Need a fused/LiDAR surface with GPS to print."
            return
        }
        let model = SiteMapPrintModel(
            projectName: projectName,
            sheet: sheet,
            heightmap: source,
            origin: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            intervalInches: contourIntervalInches,
            methodLabel: fusedResult?.method ?? "lidar_only",
            verticalBiasM: fusedResult?.verticalBiasM ?? 0,
            lidarCellCount: fusedResult?.lidarSampleCount
                ?? source.elevations.filter { !$0.isNaN }.count,
            capturedAt: Date()
        )
        do {
            sharePDFURL = try SiteMapPDFRenderer.render(model)
        } catch {
            printError = error.localizedDescription
        }
    }

    private var contourSourceHeightmap: HeightmapResult? {
        fusedResult?.heightmap ?? lidarHeightmap
    }

    private func refreshStatus() {
        if isFusing {
            statusMessage = fuseProgress ?? "Fusing USGS 3DEP + LiDAR…"
            return
        }
        if let fused = fusedResult {
            let label = contourIntervalInches < 1
                ? String(format: "%.3g in", contourIntervalInches)
                : String(format: "%.2g in", contourIntervalInches)
            statusMessage =
                "Fused map @ \(label) — 3DEP foundation + \(fused.lidarSampleCount) LiDAR cells (\(contourPolylines.count) segments)."
            if !didFitScanRegion, let lat = orientation.latitude, let lon = orientation.longitude {
                region = ContourMapGeoref.region(
                    heightmap: fused.heightmap,
                    origin: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
                didFitScanRegion = true
            }
        } else if lidarHeightmap != nil, orientation.latitude != nil {
            statusMessage = "LiDAR contours on topo — fuse pending or unavailable."
        } else if lidarHeightmap != nil {
            statusMessage = "Scan loaded — need GPS to place and fuse."
        } else {
            statusMessage = "USGS topo — scan a pad to fuse LiDAR detail."
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
                if lidarHeightmap == nil {
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
            if firstFix, lidarHeightmap == nil {
                region = MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
            }
            if lidarHeightmap == nil {
                statusMessage = String(
                    format: "GPS %.5f, %.5f (±%.0f m) — scan to fuse contours.",
                    coord.latitude,
                    coord.longitude,
                    max(location.horizontalAccuracy, 0)
                )
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if lidarHeightmap == nil {
                statusMessage = "GPS error — pan the map manually."
            }
        }
    }
}
