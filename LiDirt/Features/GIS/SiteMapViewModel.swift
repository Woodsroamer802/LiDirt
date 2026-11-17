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
    @Published var addressText: String = ""
    @Published var isGeocodingAddress = false
    /// Outline width (east–west) in feet.
    @Published var outlineWidthFeet: Double = JobSiteDefaults.defaultSideFeet
    /// Outline length (north–south) in feet.
    @Published var outlineLengthFeet: Double = JobSiteDefaults.defaultSideFeet
    /// When on, width/length stay equal (square).
    @Published var linkSquareSides = true
    /// When on and a Job Site exists, pan/zoom stays inside that rectangle.
    @Published var lockViewToJobSite = true
    /// On-map photo-crop style Job Site editing (drag / pinch / rotate).
    @Published var isEditingJobSiteCrop = false

    /// Back-compat helper for labels — geometric mean of width × length.
    var outlineSideFeet: Double {
        sqrt(max(outlineWidthFeet, 1) * max(outlineLengthFeet, 1))
    }
    /// Custom map built from 3DEP + LiDAR + GPS (hillshade + contours) — sharp at pad scale.
    @Published var fusedMapImage: UIImage?
    @Published var fusedMapBounds: JobSiteBounds?
    @Published var showFusedSurfaceMap = true
    @Published var isBuildingFusedMap = false
    /// Full-screen pinch-zoom viewer for the finished contour / hillshade image only.
    @Published var showContourMapViewer = false
    /// When true, hide Apple base tiles and show only the fused contour overlay on the Job Site map.
    @Published var fusedMapOnly = false
    /// OpenStreetMap building outlines (shaded) on the Job Site / fused map.
    @Published var showBuildings = true
    @Published var buildingFootprints: [BuildingFootprint] = []
    @Published var isLoadingBuildings = false
    /// 3DEP-only foundation DEM when no LiDAR scan is loaded yet.
    private var foundationHeightmap: HeightmapResult?
    private var foundationOrigin: CLLocationCoordinate2D?
    private var foundationTask: Task<Void, Never>?

    let projectName: String
    let projectId: UUID?
    var onSurfaceModeChange: ((ContourSurfaceMode) -> Void)?
    var onJobSiteChange: ((JobSiteBounds?) -> Void)?
    private let locationManager = CLLocationManager()
    private let lidarHeightmap: HeightmapResult?
    private let orientation: ScanOrientationSnapshot
    private let elevationService: USGSElevationService
    private let buildingService: BuildingFootprintService
    private let offlineStore: JobSiteOfflineStore
    private var fuseTask: Task<Void, Never>?
    private var offlineTask: Task<Void, Never>?
    private var contourTask: Task<Void, Never>?
    private var buildingsTask: Task<Void, Never>?
    private var didFitScanRegion = false
    private var cachedPreparedKey: String?
    private var cachedPreparedDEM: HeightmapResult?
    private var cropEditBaseline: JobSiteBounds?
    private var lockBeforeCropEdit = true

    init(
        projectName: String = "Site",
        projectId: UUID? = nil,
        heightmap: HeightmapResult? = nil,
        orientation: ScanOrientationSnapshot = .unavailable,
        contourIntervalInches: Double = ContourPreview.defaultIntervalInches,
        contourSurfaceMode: ContourSurfaceMode = .smoothedGround,
        jobSite: JobSiteBounds? = nil,
        initialAddress: String? = nil,
        elevationService: USGSElevationService = USGSElevationService(),
        buildingService: BuildingFootprintService = BuildingFootprintService(),
        offlineStore: JobSiteOfflineStore = JobSiteOfflineStore()
    ) {
        self.projectName = projectName
        self.projectId = projectId
        self.lidarHeightmap = heightmap
        self.orientation = orientation
        self.contourIntervalInches = max(contourIntervalInches, 0.01)
        self.contourSurfaceMode = contourSurfaceMode
        self.jobSite = jobSite
        self.addressText = initialAddress ?? ""
        self.elevationService = elevationService
        self.buildingService = buildingService
        self.offlineStore = offlineStore
        if let jobSite, jobSite.isValid {
            // Assign stored properties directly — cannot call methods before super.init.
            self.outlineWidthFeet = JobSiteDefaults.clampSideFeet(jobSite.widthFeet)
            self.outlineLengthFeet = JobSiteDefaults.clampSideFeet(jobSite.lengthFeet)
            self.linkSquareSides = abs(jobSite.widthFeet - jobSite.lengthFeet) < 1.5
            self.lockViewToJobSite = true
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
        refreshBuildingFootprints()
    }

    func onAppear() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        refreshOfflineAvailability()
        refreshBuildingFootprints()
        if lidarHeightmap == nil {
            statusMessage = "USGS topo — set a Job Site, then open Contour map for a sharp pad view."
            startFoundationMapIfNeeded()
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
        contourTask?.cancel()
        foundationTask?.cancel()
        buildingsTask?.cancel()
    }

    func setShowBuildings(_ enabled: Bool) {
        showBuildings = enabled
        if enabled {
            refreshBuildingFootprints(force: buildingFootprints.isEmpty)
            // Rebake fused image so Contour map viewer includes shading.
            if fusedMapImage != nil {
                rebuildContours()
            }
        }
    }

    var hasContourMapImage: Bool {
        fusedMapImage != nil || offlineImage != nil
    }

    var canOpenContourMap: Bool {
        hasContourMapImage || (jobSite?.isValid == true) || rawContourSourceHeightmap != nil
    }

    /// Image shown in the Contour map sheet (fused render preferred, else offline snapshot).
    var contourMapViewerImage: UIImage? {
        fusedMapImage ?? offlineImage
    }

    var contourMapViewerSubtitle: String {
        if lidarHeightmap != nil {
            return "Fused 3DEP + LiDAR contour map"
        }
        return "USGS 3DEP hillshade + contours — sharp at pad zoom"
    }

    /// Open a viewer that shows only the finished contour / hillshade map (no Apple tiles).
    func openContourMapViewer() {
        // Prefer an already-rendered image (fused or offline snapshot).
        if contourMapViewerImage != nil {
            showContourMapViewer = true
            return
        }
        // Build 3DEP (or rebuild fused) then open.
        if lidarHeightmap != nil, orientation.latitude != nil {
            showFusedSurfaceMap = true
            rebuildContours()
            statusMessage = "Building contour map…"
            // Viewer opens once image lands — polled via show when image available.
            waitAndOpenContourViewer()
            return
        }
        guard jobSite?.isValid == true else {
            contourNote = "Set a Job Site outline first, then open Contour map."
            return
        }
        startFoundationMapIfNeeded(force: true, openViewerWhenReady: true)
    }

    func setFusedMapOnly(_ enabled: Bool) {
        fusedMapOnly = enabled
        if enabled {
            showFusedSurfaceMap = true
            showTopo = false
            if fusedMapImage == nil {
                if lidarHeightmap != nil {
                    rebuildContours()
                } else {
                    startFoundationMapIfNeeded(force: true)
                }
            }
            if let bounds = fusedMapBounds ?? jobSite {
                region = bounds.region
            }
            statusMessage = enabled
                ? "Contour map only — Apple tiles hidden."
                : statusMessage
        } else {
            showTopo = true
            refreshStatus()
        }
    }

    private func waitAndOpenContourViewer() {
        foundationTask?.cancel()
        foundationTask = Task {
            for _ in 0..<40 {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 250_000_000)
                if fusedMapImage != nil || offlineImage != nil {
                    showContourMapViewer = true
                    return
                }
            }
            if fusedMapImage == nil {
                offlineError = "Could not build contour map yet — check network / Job Site size."
            }
        }
    }

    /// Fetch USGS 3DEP for the Job Site and render a sharp hillshade+contour image (no LiDAR needed).
    func startFoundationMapIfNeeded(force: Bool = false, openViewerWhenReady: Bool = false) {
        guard lidarHeightmap == nil else { return }
        guard let bounds = jobSite, bounds.isValid else { return }
        if !force, fusedMapImage != nil, foundationHeightmap != nil { return }
        if isBuildingFusedMap, !force { return }

        foundationTask?.cancel()
        isBuildingFusedMap = true
        statusMessage = "Downloading USGS elevation for contour map…"
        let interval = contourIntervalInches
        let showLines = showContours
        let wantBuildings = showBuildings
        let buildingService = buildingService
        foundationTask = Task {
            do {
                async let demFetch = elevationService.fetchFoundationDEM(covering: bounds)
                async let buildingFetch: [BuildingFootprint] = {
                    guard wantBuildings else { return [] }
                    return (try? await buildingService.fetchBuildings(covering: bounds)) ?? []
                }()
                let fetched = try await demFetch
                let buildings = await buildingFetch
                if Task.isCancelled { return }
                foundationHeightmap = fetched.heightmap
                foundationOrigin = fetched.origin
                if wantBuildings, !buildings.isEmpty {
                    buildingFootprints = buildings
                }
                let prepared = await Task.detached(priority: .userInitiated) {
                    DEMGroundSmoother.prepareForContours(fetched.heightmap, mode: .smoothedGround)
                }.value
                if Task.isCancelled { return }
                let rendered = await Task.detached(priority: .userInitiated) {
                    FusedSiteMapRenderer.render(
                        heightmap: prepared,
                        origin: fetched.origin,
                        bounds: bounds,
                        intervalInches: interval,
                        drawContours: showLines,
                        buildings: buildings
                    )
                }.value
                if Task.isCancelled { return }
                if let rendered, let image = rendered.image {
                    fusedMapImage = image
                    fusedMapBounds = rendered.bounds
                    showFusedSurfaceMap = true
                    statusMessage = String(
                        format: "3DEP contour map ready — ~%.0f×%.0f ft (scan later for LiDAR detail).",
                        bounds.widthFeet,
                        bounds.lengthFeet
                    )
                    if openViewerWhenReady {
                        showContourMapViewer = true
                    }
                } else {
                    offlineError = "Elevation downloaded but contour render failed."
                }
            } catch {
                if Task.isCancelled { return }
                statusMessage = "Could not load 3DEP contour map — \(error.localizedDescription)"
                if openViewerWhenReady {
                    offlineError = error.localizedDescription
                }
            }
            isBuildingFusedMap = false
            foundationTask = nil
        }
    }

    /// Bounds used for the fused surface map (Job Site outline, else DEM footprint).
    var fusedRenderBounds: JobSiteBounds? {
        if let jobSite, jobSite.isValid { return jobSite }
        guard let raw = rawContourSourceHeightmap,
              let lat = orientation.latitude,
              let lon = orientation.longitude else { return nil }
        return JobSiteBounds.from(
            heightmap: raw,
            origin: CLLocationCoordinate2D(latitude: lat, longitude: lon)
        )
    }

    var hasOfflinePackage: Bool {
        offlineMeta != nil
    }

    func setJobSiteFromCurrentView() {
        let bounds = JobSiteBounds.from(region: region)
        syncOutlineDimensions(from: bounds)
        linkSquareSides = abs(bounds.sideFeetNS - bounds.sideFeetEW) < 1.5
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
        syncOutlineDimensions(from: bounds)
        linkSquareSides = abs(bounds.sideFeetNS - bounds.sideFeetEW) < 1.5
        applyJobSite(bounds)
        zoomToJobSite()
    }

    /// Place / resize the outline using current width × length (feet).
    func placeOutlineAtMapCenter() {
        let width = JobSiteDefaults.clampSideFeet(outlineWidthFeet)
        let length = JobSiteDefaults.clampSideFeet(outlineLengthFeet)
        outlineWidthFeet = width
        outlineLengthFeet = length
        let center = userCoordinate ?? region.center
        let rotation = jobSite?.rotationDegrees ?? 0
        applyJobSite(JobSiteBounds.rectangle(
            center: center,
            widthFeet: width,
            lengthFeet: length,
            rotationDegrees: rotation
        ))
        zoomToJobSite()
    }

    /// Enter photo-crop style editing on the map (drag / pinch / twist).
    func beginJobSiteCropEdit() {
        if fusedMapOnly {
            fusedMapOnly = false
            showTopo = true
        }
        if jobSite == nil || jobSite?.isValid != true {
            placeOutlineAtMapCenter()
        }
        guard let current = jobSite, current.isValid else { return }
        cropEditBaseline = current
        lockBeforeCropEdit = lockViewToJobSite
        lockViewToJobSite = false
        isEditingJobSiteCrop = true
        var preview = current.region
        preview.span.latitudeDelta *= 1.65
        preview.span.longitudeDelta *= 1.65
        region = preview
        statusMessage = "Drag to move · pinch to resize · twist to rotate"
    }

    /// Live update while fingers are on the crop frame (no DEM rebuild until Done).
    func updateJobSiteFromCrop(_ bounds: JobSiteBounds) {
        guard isEditingJobSiteCrop else { return }
        jobSite = bounds
        syncOutlineDimensions(from: bounds)
        linkSquareSides = abs(bounds.widthFeet - bounds.lengthFeet) < 1.5
        statusMessage = String(
            format: "%.0f × %.0f ft · %.0f°",
            bounds.widthFeet,
            bounds.lengthFeet,
            bounds.rotationDegrees.truncatingRemainder(dividingBy: 360)
        )
    }

    func finishJobSiteCropEdit(save: Bool) {
        guard isEditingJobSiteCrop else { return }
        isEditingJobSiteCrop = false
        if save, let jobSite, jobSite.isValid {
            applyJobSite(jobSite)
            zoomToJobSite()
        } else if let baseline = cropEditBaseline {
            applyJobSite(baseline, announce: false)
            syncOutlineDimensions(from: baseline)
            linkSquareSides = abs(baseline.widthFeet - baseline.lengthFeet) < 1.5
            region = baseline.region
            statusMessage = "Job Site crop cancelled"
        }
        lockViewToJobSite = lockBeforeCropEdit
        cropEditBaseline = nil
    }

    func updateOutlineWidthFeet(_ feet: Double) {
        let clamped = JobSiteDefaults.clampSideFeet(feet)
        outlineWidthFeet = clamped
        if linkSquareSides { outlineLengthFeet = clamped }
        applyCurrentOutlineDimensions(announce: false)
    }

    func updateOutlineLengthFeet(_ feet: Double) {
        let clamped = JobSiteDefaults.clampSideFeet(feet)
        outlineLengthFeet = clamped
        if linkSquareSides { outlineWidthFeet = clamped }
        applyCurrentOutlineDimensions(announce: false)
    }

    func setLinkSquareSides(_ linked: Bool) {
        linkSquareSides = linked
        if linked {
            let side = JobSiteDefaults.clampSideFeet((outlineWidthFeet + outlineLengthFeet) / 2)
            outlineWidthFeet = side
            outlineLengthFeet = side
            applyCurrentOutlineDimensions(announce: false)
        }
    }

    /// Move the existing outline (or create one) so its center matches the current map center.
    func moveJobSiteToMapCenter() {
        let center = region.center
        if let jobSite {
            applyJobSite(jobSite.recentered(to: center))
        } else {
            placeOutlineAtMapCenter()
            return
        }
        zoomToJobSite()
    }

    func moveJobSiteToGPS() {
        guard let coord = userCoordinate else {
            contourNote = "No GPS fix yet — wait for location or move to map center."
            return
        }
        if let jobSite {
            applyJobSite(jobSite.recentered(to: coord))
        } else {
            let width = JobSiteDefaults.clampSideFeet(outlineWidthFeet)
            let length = JobSiteDefaults.clampSideFeet(outlineLengthFeet)
            applyJobSite(JobSiteBounds.rectangle(center: coord, widthFeet: width, lengthFeet: length))
        }
        zoomToJobSite()
    }

    func nudgeJobSite(eastFeet: Double, northFeet: Double) {
        guard let jobSite else {
            placeOutlineAtMapCenter()
            return
        }
        applyJobSite(jobSite.nudged(eastFeet: eastFeet, northFeet: northFeet))
        if lockViewToJobSite, let updated = self.jobSite {
            region = updated.region
        }
    }

    func clearJobSite() {
        applyJobSite(nil)
    }

    func zoomToJobSite() {
        guard let jobSite, jobSite.isValid else { return }
        region = jobSite.region
    }

    private func applyCurrentOutlineDimensions(announce: Bool) {
        let width = JobSiteDefaults.clampSideFeet(outlineWidthFeet)
        let length = JobSiteDefaults.clampSideFeet(outlineLengthFeet)
        outlineWidthFeet = width
        outlineLengthFeet = length
        let center = jobSite?.center ?? userCoordinate ?? region.center
        let rotation = jobSite?.rotationDegrees ?? 0
        let bounds = JobSiteBounds.rectangle(
            center: center,
            widthFeet: width,
            lengthFeet: length,
            rotationDegrees: rotation
        )
        applyJobSite(bounds, announce: announce)
        if lockViewToJobSite {
            region = bounds.region
        }
    }

    private func syncOutlineDimensions(from bounds: JobSiteBounds) {
        outlineWidthFeet = JobSiteDefaults.clampSideFeet(bounds.widthFeet)
        outlineLengthFeet = JobSiteDefaults.clampSideFeet(bounds.lengthFeet)
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
                let origin: CLLocationCoordinate2D? = {
                    guard let lat = orientation.latitude, let lon = orientation.longitude else { return nil }
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }()
                let meta = try await offlineStore.save(
                    projectId: projectId,
                    projectName: projectName,
                    bounds: jobSite,
                    contourPolylines: contourPolylines,
                    contourIntervalInches: contourIntervalInches,
                    surfaceMode: contourSurfaceMode,
                    heightmap: preparedContourSource(),
                    origin: origin
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
                statusMessage = "Job Site offline map saved (\(meta.imageWidthPx)×\(meta.imageHeightPx))."
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

    /// Geocode an address, frame a Job Site at the current outline size, then download for offline use.
    func downloadTopoForAddress() {
        let query = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            offlineError = "Enter a street address or place name."
            return
        }
        let widthFeet = JobSiteDefaults.clampSideFeet(outlineWidthFeet)
        let lengthFeet = JobSiteDefaults.clampSideFeet(outlineLengthFeet)
        outlineWidthFeet = widthFeet
        outlineLengthFeet = lengthFeet
        isGeocodingAddress = true
        offlineProgress = "Looking up address…"
        offlineError = nil
        offlineTask?.cancel()
        offlineTask = Task {
            do {
                let marks = try await CLGeocoder().geocodeAddressString(query)
                guard let mark = marks.first, let location = mark.location else {
                    throw JobSiteOfflineError.addressNotFound
                }
                if Task.isCancelled { return }
                let coord = location.coordinate
                let bounds = JobSiteBounds.rectangle(
                    center: coord,
                    widthFeet: widthFeet,
                    lengthFeet: lengthFeet
                )
                applyJobSite(bounds)
                region = bounds.region
                userCoordinate = coord
                isGeocodingAddress = false
                offlineProgress = String(
                    format: "Downloading ~%.0f×%.0f ft topo for %@…",
                    widthFeet, lengthFeet, query
                )
                rebuildContours()
                statusMessage = "Address found — downloading topo + LiDAR layer for offline…"
                guard let projectId else {
                    isGeocodingAddress = false
                    offlineProgress = nil
                    offlineError = "Open this map from a project to save offline topo."
                    return
                }
                let origin: CLLocationCoordinate2D? = {
                    guard let lat = self.orientation.latitude, let lon = self.orientation.longitude else { return nil }
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }()
                let meta = try await offlineStore.save(
                    projectId: projectId,
                    projectName: projectName,
                    bounds: bounds,
                    contourPolylines: contourPolylines,
                    contourIntervalInches: contourIntervalInches,
                    surfaceMode: contourSurfaceMode,
                    heightmap: preparedContourSource(),
                    origin: origin
                ) { [weak self] message in
                    Task { @MainActor in
                        self?.offlineProgress = message
                    }
                }
                if Task.isCancelled { return }
                offlineMeta = meta
                offlineImage = offlineStore.loadImage(projectId: projectId)
                offlineProgress = nil
                let lidarNote = contourPolylines.isEmpty
                    ? "Topo foundation only (scan on site to fuse LiDAR into the map)."
                    : "Fused 3DEP + LiDAR map ready offline."
                statusMessage = String(
                    format: "Offline Job Site ready (~%.0f×%.0f ft) for %@. %@",
                    widthFeet, lengthFeet, query, lidarNote
                )
            } catch {
                if Task.isCancelled { return }
                isGeocodingAddress = false
                offlineProgress = nil
                offlineError = error.localizedDescription
            }
        }
    }

    private func applyJobSite(_ bounds: JobSiteBounds?, announce: Bool = true) {
        jobSite = bounds
        onJobSiteChange?(bounds)
        if announce, let bounds {
            let rotationNote = abs(bounds.rotationDegrees.truncatingRemainder(dividingBy: 360)) < 0.5
                ? ""
                : String(format: " · %.0f°", bounds.rotationDegrees.truncatingRemainder(dividingBy: 360))
            statusMessage = String(
                format: "Job Site set — ~%.0f × %.0f ft%@.",
                bounds.widthFeet,
                bounds.lengthFeet,
                rotationNote
            )
        }
        refreshBuildingFootprints(force: true)
        // Re-render fused surface for the new outline size.
        if lidarHeightmap != nil, orientation.latitude != nil {
            rebuildContours()
        } else if bounds?.isValid == true {
            // Invalidate prior foundation so the new outline gets a fresh 3DEP map.
            foundationHeightmap = nil
            foundationOrigin = nil
            fusedMapImage = nil
            fusedMapBounds = nil
            startFoundationMapIfNeeded(force: true)
        } else {
            foundationHeightmap = nil
            foundationOrigin = nil
            fusedMapImage = nil
            fusedMapBounds = nil
            buildingFootprints = []
        }
    }

    /// Load OSM building footprints for the current Job Site (or map region).
    func refreshBuildingFootprints(force: Bool = false) {
        guard showBuildings else { return }
        let queryBounds: (south: Double, west: Double, north: Double, east: Double)?
        if let jobSite, jobSite.isValid {
            queryBounds = (jobSite.south, jobSite.west, jobSite.north, jobSite.east)
        } else {
            let c = region.center
            let dLat = max(region.span.latitudeDelta * 0.5, 0.0004)
            let dLon = max(region.span.longitudeDelta * 0.5, 0.0004)
            queryBounds = (c.latitude - dLat, c.longitude - dLon, c.latitude + dLat, c.longitude + dLon)
        }
        guard let queryBounds else { return }
        if !force, !buildingFootprints.isEmpty, isLoadingBuildings { return }

        buildingsTask?.cancel()
        isLoadingBuildings = true
        let service = buildingService
        buildingsTask = Task {
            do {
                let footprints = try await service.fetchBuildings(
                    south: queryBounds.south,
                    west: queryBounds.west,
                    north: queryBounds.north,
                    east: queryBounds.east
                )
                if Task.isCancelled { return }
                let changed = footprints != buildingFootprints
                buildingFootprints = footprints
                isLoadingBuildings = false
                // Bake into fused image once footprints arrive.
                if changed, fusedMapImage != nil || foundationHeightmap != nil || fusedResult != nil {
                    rebuildContours()
                }
            } catch {
                if Task.isCancelled { return }
                isLoadingBuildings = false
                // Soft-fail — map still works without buildings.
            }
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
        let lidar = lidarHeightmap
        fuseTask = Task {
            do {
                let foundation = try await service.fetchFoundationDEM(
                    covering: lidar,
                    origin: origin
                )
                if Task.isCancelled { return }
                fuseProgress = "Blending LiDAR into foundation…"
                statusMessage = fuseProgress ?? "Fusing…"
                let fused = await Task.detached(priority: .userInitiated) {
                    FusedDEMBuilder.fuse(foundation: foundation, lidar: lidar)
                }.value
                if Task.isCancelled { return }
                fusedResult = fused
                cachedPreparedKey = nil
                cachedPreparedDEM = nil
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
                contourNote = "3DEP unavailable (\(error.localizedDescription)). Showing LiDAR-only fused map."
                fusedResult = nil
                rebuildContours()
                refreshStatus()
            }
        }
    }

    func rebuildContours() {
        let originCoord: CLLocationCoordinate2D?
        if let lat = orientation.latitude, let lon = orientation.longitude {
            originCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            originCoord = foundationOrigin
        }
        guard let origin = originCoord,
              let raw = rawContourSourceHeightmap else {
            contourPolylines = []
            if lidarHeightmap == nil {
                // Keep any 3DEP foundation image; don't blank the map while GPS-only.
            } else {
                fusedMapImage = nil
                fusedMapBounds = nil
            }
            if lidarHeightmap != nil, orientation.latitude == nil {
                contourNote = GISDisclaimer.needScanGPS
            }
            return
        }
        let interval = contourIntervalInches
        let mode = contourSurfaceMode
        let showLines = showContours
        let buildSurface = showFusedSurfaceMap
        let renderBounds = fusedRenderBounds
        let key = "\(fusedResult?.method ?? "lidar")-\(mode.rawValue)-\(raw.width)x\(raw.height)"

        contourTask?.cancel()
        isBuildingFusedMap = buildSurface
        contourTask = Task(priority: .userInitiated) {
            let prepared: HeightmapResult
            if let cachedPreparedDEM, cachedPreparedKey == key {
                prepared = cachedPreparedDEM
            } else {
                prepared = await Task.detached(priority: .userInitiated) {
                    DEMGroundSmoother.prepareForContours(raw, mode: mode)
                }.value
            }
            if Task.isCancelled { return }

            let lines: [ContourMapGeoref.ContourPolyline]
            if showLines {
                lines = await Task.detached(priority: .userInitiated) {
                    ContourMapGeoref.polylines(
                        heightmap: prepared,
                        origin: origin,
                        intervalInches: interval
                    )
                }.value
            } else {
                lines = []
            }
            if Task.isCancelled { return }

            let buildings = showBuildings ? buildingFootprints : []
            var rendered: FusedSiteMapRenderer.RenderedMap?
            if buildSurface, let renderBounds {
                rendered = await Task.detached(priority: .userInitiated) {
                    FusedSiteMapRenderer.render(
                        heightmap: prepared,
                        origin: origin,
                        bounds: renderBounds,
                        intervalInches: interval,
                        drawContours: showLines,
                        buildings: buildings
                    )
                }.value
            }
            if Task.isCancelled { return }

            cachedPreparedKey = key
            cachedPreparedDEM = prepared
            // Prefer the fused surface image (contours baked in) — avoids MapKit overlay thrash.
            if let rendered, let image = rendered.image {
                fusedMapImage = image
                fusedMapBounds = rendered.bounds
                contourPolylines = []
            } else {
                fusedMapImage = nil
                fusedMapBounds = nil
                contourPolylines = lines
            }
            isBuildingFusedMap = false
            if fusedResult == nil, !isFusing, contourNote == nil, !orientation.frameAlignedToNorth {
                contourNote = "Map placed with GPS; scan was not north-aligned — orientation is approximate."
            }
            refreshStatus()
        }
    }

    private func preparedContourSource() -> HeightmapResult? {
        if let cachedPreparedDEM { return cachedPreparedDEM }
        return contourSourceHeightmap
    }

    func regionDidChange(_ newRegion: MKCoordinateRegion) {
        region = newRegion
    }

    var canExportPrint: Bool {
        guard contourSourceHeightmap != nil else { return false }
        if orientation.latitude != nil, orientation.longitude != nil { return true }
        return foundationOrigin != nil
    }

    func exportPDF(sheet: PrintSheetSize) {
        printError = nil
        sharePDFURL = nil
        let origin: CLLocationCoordinate2D?
        if let lat = orientation.latitude, let lon = orientation.longitude {
            origin = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            origin = foundationOrigin
        }
        guard let source = contourSourceHeightmap, let origin else {
            printError = "Need a contour surface (scan or 3DEP Job Site map) to print."
            return
        }
        let method = (fusedResult?.method
            ?? (lidarHeightmap != nil ? "lidar_only" : "3dep_foundation"))
            + "/" + contourSurfaceMode.rawValue
        let model = SiteMapPrintModel(
            projectName: projectName,
            sheet: sheet,
            heightmap: source,
            origin: origin,
            intervalInches: contourIntervalInches,
            methodLabel: method,
            surfaceModeLabel: contourSurfaceMode.label,
            verticalBiasM: fusedResult?.verticalBiasM ?? 0,
            lidarCellCount: fusedResult?.lidarSampleCount
                ?? (lidarHeightmap != nil ? source.elevations.filter { !$0.isNaN }.count : 0),
            capturedAt: Date()
        )
        do {
            sharePDFURL = try SiteMapPDFRenderer.render(model)
        } catch {
            printError = error.localizedDescription
        }
    }

    private var rawContourSourceHeightmap: HeightmapResult? {
        fusedResult?.heightmap ?? lidarHeightmap ?? foundationHeightmap
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
            let mapNote = fusedMapImage == nil ? "building map…" : "fused surface map ready"
            statusMessage =
                "Fused \(surface) @ \(label) — 3DEP + \(fused.lidarSampleCount) LiDAR cells · \(mapNote)."
            // Prefer the outlined Job Site; never yank the camera to the raw DEM footprint when locked.
            if !didFitScanRegion {
                if let jobSite, jobSite.isValid {
                    region = jobSite.region
                    didFitScanRegion = true
                } else if let lat = orientation.latitude, let lon = orientation.longitude {
                    region = ContourMapGeoref.region(
                        heightmap: fused.heightmap,
                        origin: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    )
                    didFitScanRegion = true
                }
            }
        } else if lidarHeightmap != nil, orientation.latitude != nil {
            statusMessage = "LiDAR \(surface) contours on topo — fuse pending or unavailable."
        } else if lidarHeightmap != nil {
            statusMessage = "Scan loaded — need GPS to place and fuse."
        } else if fusedMapImage != nil {
            statusMessage = "3DEP contour map ready — open Contour map for a sharp pad view."
        } else if jobSite?.isValid == true {
            statusMessage = "Job Site set — building contour map from USGS elevation…"
        } else {
            statusMessage = "USGS topo — set a Job Site, then open Contour map."
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
            if firstFix, lidarHeightmap == nil, jobSite == nil {
                region = MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
            }
            if lidarHeightmap == nil, fusedMapImage == nil, !isBuildingFusedMap {
                statusMessage = String(
                    format: "GPS %.5f, %.5f (±%.0f m) — set Job Site, then Contour map.",
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
