import SwiftUI
import MapKit

struct SiteMapView: View {
    @StateObject private var viewModel: SiteMapViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var intervalText: String
    @State private var showPrintSheet = false
    var onIntervalChange: ((Double) -> Void)?
    var onSurfaceModeChange: ((ContourSurfaceMode) -> Void)?
    var onJobSiteChange: ((JobSiteBounds?) -> Void)?

    init(
        projectName: String = "Site",
        projectId: UUID? = nil,
        heightmap: HeightmapResult? = nil,
        orientation: ScanOrientationSnapshot = .unavailable,
        contourIntervalInches: Double = ContourPreview.defaultIntervalInches,
        contourSurfaceMode: ContourSurfaceMode = .smoothedGround,
        jobSite: JobSiteBounds? = nil,
        onIntervalChange: ((Double) -> Void)? = nil,
        onSurfaceModeChange: ((ContourSurfaceMode) -> Void)? = nil,
        onJobSiteChange: ((JobSiteBounds?) -> Void)? = nil
    ) {
        let vm = SiteMapViewModel(
            projectName: projectName,
            projectId: projectId,
            heightmap: heightmap,
            orientation: orientation,
            contourIntervalInches: contourIntervalInches,
            contourSurfaceMode: contourSurfaceMode,
            jobSite: jobSite
        )
        vm.onSurfaceModeChange = onSurfaceModeChange
        vm.onJobSiteChange = onJobSiteChange
        _viewModel = StateObject(wrappedValue: vm)
        _intervalText = State(initialValue: Self.formatInterval(contourIntervalInches))
        self.onIntervalChange = onIntervalChange
        self.onSurfaceModeChange = onSurfaceModeChange
        self.onJobSiteChange = onJobSiteChange
    }

    var body: some View {
        ZStack(alignment: .top) {
            SiteMapRepresentable(viewModel: viewModel)
                .ignoresSafeArea(edges: .bottom)

            VStack(alignment: .leading, spacing: 10) {
                header
                Spacer()
                footer
            }
            .padding(16)
        }
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .navigationTitle("Fused site map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Print") { showPrintSheet = true }
                    .disabled(!viewModel.canExportPrint)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showPrintSheet) {
            PrintMapSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showOfflineViewer) {
            if let image = viewModel.offlineImage {
                OfflineJobSiteView(
                    projectName: viewModel.projectName,
                    image: image,
                    meta: viewModel.offlineMeta
                )
            }
        }
        .sheet(item: Binding(
            get: { viewModel.sharePDFURL.map(IdentifiableURL.init) },
            set: { viewModel.sharePDFURL = $0?.url }
        )) { item in
            ActivityView(activityItems: [item.url])
        }
        .alert("Print failed", isPresented: Binding(
            get: { viewModel.printError != nil },
            set: { if !$0 { viewModel.printError = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.printError = nil }
        } message: {
            Text(viewModel.printError ?? "")
        }
        .alert("Offline save", isPresented: Binding(
            get: { viewModel.offlineError != nil },
            set: { if !$0 { viewModel.offlineError = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.offlineError = nil }
        } message: {
            Text(viewModel.offlineError ?? "")
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.statusMessage)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textPrimary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                toggleChip("USGS topo", isOn: $viewModel.showTopo)
                toggleChip("Fused contours", isOn: Binding(
                    get: { viewModel.showContours },
                    set: { newValue in
                        viewModel.showContours = newValue
                        viewModel.rebuildContours()
                    }
                ))
                toggleChip("Job Site", isOn: $viewModel.showJobSiteOverlay)
                if viewModel.isFusing || viewModel.isSavingOffline {
                    ProgressView()
                        .tint(LiDirtColors.constructionYellow)
                }
            }

            jobSiteControls

            VStack(alignment: .leading, spacing: 6) {
                Text("Ground detail")
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textSecondary)
                Picker("Ground detail", selection: Binding(
                    get: { viewModel.contourSurfaceMode },
                    set: { viewModel.setContourSurfaceMode($0) }
                )) {
                    ForEach(ContourSurfaceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(viewModel.contourSurfaceMode.shortHelp)
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textMuted)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 8) {
                Text("Interval (in)")
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textSecondary)
                TextField("0.125", text: $intervalText)
                    .keyboardType(.decimalPad)
                    .font(LiDirtTypography.mono)
                    .foregroundStyle(LiDirtColors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(LiDirtColors.gunmetalElevated, in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: 120)
                Button("Apply") {
                    applyInterval()
                }
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.gunmetalDeep)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(LiDirtColors.constructionYellow, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

            if let progress = viewModel.offlineProgress {
                Text(progress)
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.constructionYellow)
            }

            if let note = viewModel.contourNote {
                Text(note)
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.gunmetalDeep)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LiDirtColors.constructionYellow, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var jobSiteControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Job Site")
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textSecondary)
            Text("Draw a rectangle over the work area for phone zoom. Save a high-res snapshot for offline pan / zoom / rotate.")
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    jobButton("From view") { viewModel.setJobSiteFromCurrentView() }
                    jobButton("From scan") { viewModel.setJobSiteFromScan() }
                    jobButton("~260 ft square") { viewModel.setSquareJobSite(halfSideMeters: 40) }
                    jobButton("Zoom") { viewModel.zoomToJobSite() }
                        .disabled(viewModel.jobSite == nil)
                    jobButton("Clear", destructive: true) { viewModel.clearJobSite() }
                        .disabled(viewModel.jobSite == nil)
                }
            }

            HStack(spacing: 8) {
                jobButton(viewModel.hasOfflinePackage ? "Update offline" : "Save offline") {
                    viewModel.saveJobSiteOffline()
                }
                .disabled(viewModel.jobSite == nil || viewModel.isSavingOffline || viewModel.projectId == nil)

                jobButton("Open offline") { viewModel.openOfflineJobSite() }
                    .disabled(!viewModel.hasOfflinePackage)

                if viewModel.hasOfflinePackage {
                    jobButton("Delete offline", destructive: true) { viewModel.deleteOfflineJobSite() }
                }
            }

            if viewModel.hasOfflinePackage, let meta = viewModel.offlineMeta {
                Text("Offline ready · \(meta.imageWidthPx)×\(meta.imageHeightPx)px · \(meta.savedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.constructionYellow)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        Text(GISDisclaimer.topoContours)
            .font(LiDirtTypography.caption)
            .foregroundStyle(LiDirtColors.textMuted)
            .padding(12)
            .background(LiDirtColors.gunmetalDeep.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
    }

    private func applyInterval() {
        let cleaned = intervalText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else {
            intervalText = Self.formatInterval(viewModel.contourIntervalInches)
            return
        }
        viewModel.setContourIntervalInches(value)
        intervalText = Self.formatInterval(viewModel.contourIntervalInches)
        onIntervalChange?(viewModel.contourIntervalInches)
    }

    private func toggleChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(LiDirtTypography.caption)
                .foregroundStyle(isOn.wrappedValue ? LiDirtColors.gunmetalDeep : LiDirtColors.constructionYellow)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        isOn.wrappedValue
                        ? LiDirtColors.constructionYellow
                        : LiDirtColors.gunmetalElevated
                    )
                )
                .overlay(
                    Capsule().stroke(LiDirtColors.constructionYellow, lineWidth: 1)
                )
        }
    }

    private func jobButton(
        _ title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(LiDirtTypography.caption)
                .foregroundStyle(destructive ? LiDirtColors.danger : LiDirtColors.gunmetalDeep)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(destructive ? LiDirtColors.gunmetalElevated : LiDirtColors.constructionYellow)
                )
        }
    }

    private static func formatInterval(_ inches: Double) -> String {
        if inches < 1 {
            return String(format: "%g", inches)
        }
        return String(format: "%.2f", inches)
    }
}

private struct PrintMapSheet: View {
    @ObservedObject var viewModel: SiteMapViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Prints a fused contour plan (USGS 3DEP foundation + LiDAR detail) fitted to the sheet with title block, scale, and north arrow.")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textSecondary)
                }
                Section("Sheet size") {
                    ForEach(PrintSheetSize.allCases) { sheet in
                        Button {
                            dismiss()
                            Task { @MainActor in
                                viewModel.exportPDF(sheet: sheet)
                            }
                        } label: {
                            Text(sheet.label)
                                .foregroundStyle(LiDirtColors.constructionYellow)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LiDirtColors.gunmetal.ignoresSafeArea())
            .navigationTitle("Print map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct SiteMapRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: SiteMapViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        map.isRotateEnabled = true
        map.setRegion(viewModel.region, animated: false)
        context.coordinator.mapView = map
        context.coordinator.applyOverlays()
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.applyOverlays()
        if abs(mapView.region.center.latitude - viewModel.region.center.latitude) > 1e-5
            || abs(mapView.region.span.latitudeDelta - viewModel.region.span.latitudeDelta) > 1e-6 {
            mapView.setRegion(viewModel.region, animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var viewModel: SiteMapViewModel
        weak var mapView: MKMapView?
        private var topoOverlay: MKTileOverlay?
        private var lastContourIDs: [String] = []
        private var lastJobSite: JobSiteBounds?
        private var showingJobSite = false

        init(viewModel: SiteMapViewModel) {
            self.viewModel = viewModel
        }

        func applyOverlays() {
            guard let mapView else { return }

            if viewModel.showTopo {
                if topoOverlay == nil {
                    let overlay = USGSTopoOverlay.makeOverlay()
                    topoOverlay = overlay
                    mapView.addOverlay(overlay, level: .aboveRoads)
                }
            } else if let topoOverlay {
                mapView.removeOverlay(topoOverlay)
                self.topoOverlay = nil
            }

            let ids = viewModel.contourPolylines.map(\.id)
            if ids != lastContourIDs {
                for overlay in mapView.overlays where overlay is MKPolyline {
                    mapView.removeOverlay(overlay)
                }
                lastContourIDs = ids
                for line in viewModel.contourPolylines {
                    var coords = line.coordinates
                    let polyline = MKPolyline(coordinates: &coords, count: coords.count)
                    polyline.title = String(format: "%.4f m", line.elevationM)
                    mapView.addOverlay(polyline, level: .aboveLabels)
                }
            }

            let job = viewModel.showJobSiteOverlay ? viewModel.jobSite : nil
            if job != lastJobSite || (job != nil) != showingJobSite {
                for overlay in mapView.overlays {
                    if let polygon = overlay as? MKPolygon, polygon.title == "Job Site" {
                        mapView.removeOverlay(polygon)
                    }
                }
                lastJobSite = job
                showingJobSite = job != nil
                if let job {
                    var coords = job.cornerCoordinates
                    let polygon = MKPolygon(coordinates: &coords, count: coords.count)
                    polygon.title = "Job Site"
                    mapView.addOverlay(polygon, level: .aboveLabels)
                }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            if let polygon = overlay as? MKPolygon, polygon.title == "Job Site" {
                let renderer = MKPolygonRenderer(polygon: polygon)
                let yellow = UIColor(red: 0.96, green: 0.78, blue: 0.12, alpha: 1)
                renderer.strokeColor = yellow
                renderer.fillColor = yellow.withAlphaComponent(0.12)
                renderer.lineWidth = 2.5
                renderer.lineDashPattern = [8, 4]
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                let yellow = UIColor(red: 0.96, green: 0.78, blue: 0.12, alpha: 1)
                renderer.strokeColor = yellow
                renderer.lineWidth = 2
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            viewModel.regionDidChange(mapView.region)
        }
    }
}
