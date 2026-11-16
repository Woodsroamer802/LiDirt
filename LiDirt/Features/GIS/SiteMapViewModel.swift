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
    @Published var contourSurfaceMode: ContourSurfaceMode
    @Published var contourPolylines: [ContourMapGeoref.ContourPolyline] = []
    @Published var statusMessage = "Locating…"
    @Published var contourNote: String?
    @Published var isFusing = false
    @Published var fuseProgress: String?
    @Published var fusedResult: FusedDEMResult?
    @Published var printError: String?
    @Published var sharePDFURL: URL?
    @Published var jobSite: JobSiteBounds?
    @Published var showJobSiteOverlay = true
    @Published var isSavingOffline = false
    @Published var offlineProgress: String?
    @Published var offlineError: String?
    @Published var offlineMeta: JobSiteOfflineMeta?
    @Published var offlineImage: UIImage?
    @Published var showOfflineViewer = false

    let projectName: String
    let projectId: UUID?
    var onSurfaceModeChange: ((ContourSurfaceMode) -> Void)?
    var onJobSiteChange: ((JobSiteBounds?) -> Void)?
    private let locationManager = CLLocationManager()
    private let lidarHeightmap: HeightmapResult?
    private let orientation: ScanOrientationSnapshot
    private let elevationService: USGSElevationService
    private let offlineStore: JobSiteOfflineStore
    private var fuseTask: Task<Void, Never>?
    private var offlineTask: Task<Void, Never>?
    private var didFitScanRegion = false

    init(
        projectName: String = "Site",
        projectId: UUID? = nil,
        heightmap: HeightmapResult? = nil,
        orientation: ScanOrientationSnapshot = .unavailable,
        contourIntervalInches: Double = ContourPreview.defaultIntervalInches,
        contourSurfaceMode: ContourSurfaceMode = .smoothedGround,
        jobSite: JobSiteBounds? = nil,
        elevationService: USGSElevationService = USGSElevationService(),
        offlineStore: JobSiteOfflineStore = JobSiteOfflineStore()
    ) {
        self.projectName = projectName
        self.projectId = projectId
        self.lidarHeightmap = heightmap
        self.orientation = orientation
        self.contourIntervalInches = max(contourIntervalInches, 0.01)
        self.contourSurfaceMode = contourSurfaceMode
        self.jobSite = jobSite
        self.elevationService = elevationService
        self.offlineStore = offlineStore

        if let jobSite, jobSite.isValid {
            region = jobSite.region
            didFitScanRegion = true
        } else if let lat = orientation.latitude, let lon = orientation.longitude {
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
        refreshOfflineAvailability()
        rebuildContours()
    }

    func onAppear() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        refreshOfflineAvailability()
        if lidarHeightmap == nil {
            statusMessage = "USGS topo — set a Job Site rectangle for phone focus / offline."
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
        offlineTask?.cancel()
    }

    var hasOfflinePackage: Bool {
        offlineMeta != nil
    }

    func setJobSiteFromCurrentView() {
        let bounds = JobSiteBounds.from(region: region)
        applyJobSite(bounds)
        zoomToJobSite()
    }

    func setJobSiteFromScan() {
        guard let heightmap = lidarHeightmap ?? fusedResult?.heightmap,
              let lat = orientation.latitude,
              let lon = orientation.longitude else {
            contourNote = "Need a GPS-tagged scan to set Job Site from the LiDAR footprint."
            return
        }
        let bounds = JobSiteBounds.from(
            heightmap: heightmap,
            origin: CLLocationCoordinate2D(latitude: lat, longitude: lon)
        )
        applyJobSite(bounds)
        zoomToJobSite()
    }

    func setSquareJobSite(halfSideMeters: Double = 40) {
        let center = userCoordinate ?? region.center
        applyJobSite(JobSiteBounds.square(center: center, halfSideMeters: halfSideMeters))
        zoomToJobSite()
    }

    func clearJobSite() {
        applyJobSite(nil)
    }

    func zoomToJobSite() {
        guard let jobSite, jobSite.isValid else { return }
        region = jobSite.region
    }

    func saveJobSiteOffline() {
        guard let projectId else {
            offlineError = "Open this map from a project to save offline."
            return
        }
        guard let jobSite, jobSite.isValid else {
            offlineError = JobSiteOfflineError.noJobSite.localizedDescription
            return
        }
        isSavingOffline = true
        offlineProgress = "Preparing offline Job Site…"
        offlineError = nil
        offlineTask?.cancel()
        offlineTask = Task {
            do {
                let meta = try await offlineStore.save(
                    projectId: projectId,
                    projectName: projectName,
                    bounds: jobSite,
                    contourPolylines: contourPolylines,
                    contourIntervalInches: contourIntervalInches,
                    surfaceMode: contourSurfaceMode
                ) { [weak self] message in
                    Task { @MainActor in
                        self?.offlineProgress = message
                    }
                }
                if Task.isCancelled { return }
                offlineMeta = meta
                offlineImage = offlineStore.loadImage(projectId: projectId)
                isSavingOffline = false
                offlineProgress = nil
                statusMessage = "Job Site offline snapshot saved (\(meta.imageWidthPx)×\(meta.imageHeightPx))."
            } catch {
                if Task.isCancelled { return }
                isSavingOffline = false
                offlineProgress = nil
                offlineError = error.localizedDescription
            }
        }
    }

    func openOfflineJobSite() {
        guard let projectId else { return }
        if offlineImage == nil {
            offlineImage = offlineStore.loadImage(projectId: projectId)
        }
        guard offlineImage != nil else {
            offlineError = "No offline Job Site image yet — save one first."
            return
        }
        showOfflineViewer = true
    }

    func deleteOfflineJobSite() {
        guard let projectId else { return }
        offlineStore.deletePackage(projectId: projectId)
        offlineMeta = nil
        offlineImage = nil
        statusMessage = "Offline Job Site removed."
    }

    private func applyJobSite(_ bounds: JobSiteBounds?) {
        jobSite = bounds
        onJobSiteChange?(bounds)
        if let bounds {
            statusMessage = String(
                format: "Job Site set — ~%.0f × %.0f ft. Zoom or save offline snapshot.",
                bounds.latitudeDelta * 364_000,
                bounds.longitudeDelta * 364_000 * cos(bounds.center.latitude * .pi / 180)
            )
        }
    }

    private func refreshOfflineAvailability() {
        guard let projectId else {
            offlineMeta = nil
            offlineImage = nil
            return
        }
        offlineMeta = offlineStore.loadMeta(projectId: projectId)
        offlineImage = offlineStore.loadImage(projectId: projectId)
    }

    func setContourIntervalInches(_ inches: Double) {
        let clamped = max(inches, 0.01)
        guard abs(clamped - contourIntervalInches) > 1e-9 else { return }
        contourIntervalInches = clamped
        rebuildContours()
        refreshStatus()
    }

    func setContourSurfaceMode(_ mode: ContourSurfaceMode) {
        guard mode != contourSurfaceMode else { return }
        contourSurfaceMode = mode
        onSurfaceModeChange?(mode)
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
        if fusedResult == nil, orientation.latitude != nil, !isFusing, contourNote == nil,
           !orientation.frameAlignedToNorth {
            contourNote = "Contours placed with GPS; scan was not north-aligned — orientation is approximate."
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
        let method = (fusedResult?.method ?? "lidar_only") + "/" + contourSurfaceMode.rawValue
        let model = SiteMapPrintModel(
            projectName: projectName,
            sheet: sheet,
            heightmap: source,
            origin: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            intervalInches: contourIntervalInches,
            methodLabel: method,
            surfaceModeLabel: contourSurfaceMode.label,
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

    private var rawContourSourceHeightmap: HeightmapResult? {
        fusedResult?.heightmap ?? lidarHeightmap
    }

    private var contourSourceHeightmap: HeightmapResult? {
        guard let raw = rawContourSourceHeightmap else { return nil }
        return DEMGroundSmoother.prepareForContours(raw, mode: contourSurfaceMode)
    }

    private func refreshStatus() {
        if isFusing {
            statusMessage = fuseProgress ?? "Fusing USGS 3DEP + LiDAR…"
            return
        }
        let surface = contourSurfaceMode == .smoothedGround ? "smoothed" : "as-scanned"
        if let fused = fusedResult {
            let label = contourIntervalInches < 1
                ? String(format: "%.3g in", contourIntervalInches)
                : String(format: "%.2g in", contourIntervalInches)
            statusMessage =
                "Fused \(surface) @ \(label) — 3DEP + \(fused.lidarSampleCount) LiDAR cells (\(contourPolylines.count) segments)."
            if !didFitScanRegion, let lat = orientation.latitude, let lon = orientation.longitude {
                region = ContourMapGeoref.region(
                    heightmap: fused.heightmap,
                    origin: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
                didFitScanRegion = true
            }
        } else if lidarHeightmap != nil, orientation.latitude != nil {
            statusMessage = "LiDAR \(surface) contours on topo — fuse pending or unavailable."
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
