import SwiftUI
import MapKit

struct SiteMapView: View {
    @StateObject private var viewModel: SiteMapViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var intervalText: String
    @State private var showPrintSheet = false
    @State private var showOptions = false
    @State private var disclaimerMinimized = false
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
        initialAddress: String? = nil,
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
            jobSite: jobSite,
            initialAddress: initialAddress
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

            VStack(alignment: .leading, spacing: 8) {
                compactHeader
                Spacer()
                footer
            }
            .padding(12)
        }
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .navigationTitle("Job Site map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        showOptions = true
                    } label: {
                        Label("Map options", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        showPrintSheet = true
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                    .disabled(!viewModel.canExportPrint)
                    if viewModel.hasOfflinePackage {
                        Button {
                            viewModel.openOfflineJobSite()
                        } label: {
                            Label("Open offline map", systemImage: "arrow.down.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(LiDirtColors.constructionYellow)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showOptions) {
            JobSiteOptionsSheet(
                viewModel: viewModel,
                intervalText: $intervalText,
                onApplyInterval: applyInterval
            )
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
        .onAppear {
            viewModel.onAppear()
            disclaimerMinimized = false
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                withAnimation(.easeInOut(duration: 0.35)) {
                    disclaimerMinimized = true
                }
            }
        }
        .onDisappear { viewModel.onDisappear() }
    }

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(viewModel.statusMessage)
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.isFusing || viewModel.isSavingOffline || viewModel.isGeocodingAddress {
                    ProgressView()
                        .tint(LiDirtColors.constructionYellow)
                }

                Button {
                    showOptions = true
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(LiDirtColors.constructionYellow)
                }
                .accessibilityLabel("Map options")
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

            if let progress = viewModel.offlineProgress {
                Text(progress)
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.constructionYellow)
                    .padding(.horizontal, 4)
            }

            if let note = viewModel.contourNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(LiDirtColors.gunmetalDeep)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LiDirtColors.constructionYellow, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var footer: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                disclaimerMinimized.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(disclaimerMinimized ? "Disclaimer" : "Planning aid — not a survey")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LiDirtColors.textSecondary)
                    Spacer()
                    Image(systemName: disclaimerMinimized ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(LiDirtColors.textMuted)
                }
                if !disclaimerMinimized {
                    Text(GISDisclaimer.topoContours)
                        .font(.system(size: 10))
                        .foregroundStyle(LiDirtColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(disclaimerMinimized ? 8 : 10)
            .background(LiDirtColors.gunmetalDeep.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
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

    private static func formatInterval(_ inches: Double) -> String {
        if inches < 1 {
            return String(format: "%g", inches)
        }
        return String(format: "%.2f", inches)
    }
}

private struct JobSiteOptionsSheet: View {
    @ObservedObject var viewModel: SiteMapViewModel
    @Binding var intervalText: String
    var onApplyInterval: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Layers") {
                    Toggle("USGS topo", isOn: $viewModel.showTopo)
                    Toggle("Fused contours", isOn: Binding(
                        get: { viewModel.showContours },
                        set: { newValue in
                            viewModel.showContours = newValue
                            viewModel.rebuildContours()
                        }
                    ))
                    Toggle("Job Site rectangle", isOn: $viewModel.showJobSiteOverlay)
                }

                Section {
                    TextField("Street address or place", text: $viewModel.addressText)
                        .textInputAutocapitalization(.words)
                    Button {
                        viewModel.downloadTopoForAddress()
                        dismiss()
                    } label: {
                        if viewModel.isGeocodingAddress || viewModel.isSavingOffline {
                            ProgressView()
                        } else {
                            Label("Download topo for address", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(
                        viewModel.addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || viewModel.projectId == nil
                        || viewModel.isGeocodingAddress
                        || viewModel.isSavingOffline
                    )
                    Text("Looks up the address, frames a Job Site, and saves a high-res topo snapshot. LiDAR contours are layered when a scan is loaded — use offline at the job.")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)
                } header: {
                    Text("Offline topo by address")
                }

                Section("Job Site") {
                    Button("Set from current map view") { viewModel.setJobSiteFromCurrentView() }
                    Button("Set from LiDAR scan") { viewModel.setJobSiteFromScan() }
                    Button("Set ~500 ft square") { viewModel.setSquareJobSite(halfSideMeters: 75) }
                    Button("Zoom to Job Site") { viewModel.zoomToJobSite() }
                        .disabled(viewModel.jobSite == nil)
                    Button("Clear Job Site", role: .destructive) { viewModel.clearJobSite() }
                        .disabled(viewModel.jobSite == nil)
                }

                Section("Offline map") {
                    Button(viewModel.hasOfflinePackage ? "Update offline snapshot" : "Save offline snapshot") {
                        viewModel.saveJobSiteOffline()
                    }
                    .disabled(viewModel.jobSite == nil || viewModel.isSavingOffline || viewModel.projectId == nil)
                    Button("Open offline map") { viewModel.openOfflineJobSite() }
                        .disabled(!viewModel.hasOfflinePackage)
                    if viewModel.hasOfflinePackage {
                        Button("Delete offline map", role: .destructive) {
                            viewModel.deleteOfflineJobSite()
                        }
                        if let meta = viewModel.offlineMeta {
                            Text("Ready · \(meta.imageWidthPx)×\(meta.imageHeightPx)px · \(meta.savedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(LiDirtTypography.caption)
                                .foregroundStyle(LiDirtColors.textMuted)
                        }
                    }
                }

                Section("Ground detail") {
                    Picker("Surface", selection: Binding(
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

                Section("Contour interval") {
                    HStack {
                        TextField("Inches", text: $intervalText)
                            .keyboardType(.decimalPad)
                        Button("Apply", action: onApplyInterval)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LiDirtColors.gunmetal.ignoresSafeArea())
            .navigationTitle("Map options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct PrintMapSheet: View {
    @ObservedObject var viewModel: SiteMapViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Prints a fused contour plan fitted to the sheet with title block, scale, and north arrow.")
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
