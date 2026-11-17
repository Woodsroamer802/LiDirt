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
        mapStack
            .background(LiDirtColors.gunmetal.ignoresSafeArea())
            .navigationTitle(viewModel.isEditingJobSiteCrop ? "Adjust Job Site" : "Job Site map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { siteMapToolbar }
            .interactiveDismissDisabled(viewModel.isEditingJobSiteCrop)
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
                offlineMapSheet
            }
            .sheet(isPresented: $viewModel.showContourMapViewer) {
                contourMapSheet
            }
            .sheet(item: sharePDFBinding) { item in
                ActivityView(activityItems: [item.url])
            }
            .alert("Print failed", isPresented: printErrorPresented) {
                Button("OK", role: .cancel) { viewModel.printError = nil }
            } message: {
                Text(viewModel.printError ?? "")
            }
            .alert("Offline save", isPresented: offlineErrorPresented) {
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

    private var mapStack: some View {
        ZStack(alignment: .top) {
            mapBackground
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.isEditingJobSiteCrop {
                    cropEditChrome
                } else {
                    compactHeader
                }
                Spacer()
                if !viewModel.isEditingJobSiteCrop {
                    footer
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var mapBackground: some View {
        if viewModel.fusedMapOnly, let image = viewModel.fusedMapImage {
            ContourMapCanvas(image: image)
                .ignoresSafeArea(edges: .bottom)
        } else {
            SiteMapRepresentable(viewModel: viewModel)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    @ToolbarContentBuilder
    private var siteMapToolbar: some ToolbarContent {
        if viewModel.isEditingJobSiteCrop {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { viewModel.finishJobSiteCropEdit(save: false) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { viewModel.finishJobSiteCropEdit(save: true) }
                    .fontWeight(.semibold)
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        showOptions = true
                    } label: {
                        Label("Map options", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        viewModel.beginJobSiteCropEdit()
                    } label: {
                        Label("Adjust Job Site", systemImage: "crop.rotate")
                    }
                    Button {
                        viewModel.openContourMapViewer()
                    } label: {
                        Label("Contour map", systemImage: "square.3.layers.3d.down.right")
                    }
                    .disabled(!viewModel.canOpenContourMap || viewModel.isBuildingFusedMap)
                    Button {
                        viewModel.setFusedMapOnly(!viewModel.fusedMapOnly)
                    } label: {
                        Label(
                            viewModel.fusedMapOnly ? "Show street map" : "Fused map only",
                            systemImage: viewModel.fusedMapOnly ? "map" : "map.fill"
                        )
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
    }

    @ViewBuilder
    private var offlineMapSheet: some View {
        if let image = viewModel.offlineImage {
            OfflineJobSiteView(
                projectName: viewModel.projectName,
                image: image,
                meta: viewModel.offlineMeta,
                title: "Offline Job Site"
            )
        }
    }

    @ViewBuilder
    private var contourMapSheet: some View {
        if let image = viewModel.contourMapViewerImage {
            OfflineJobSiteView(
                projectName: viewModel.projectName,
                image: image,
                meta: viewModel.offlineMeta,
                title: "Contour map",
                subtitle: viewModel.contourMapViewerSubtitle
            )
        }
    }

    private var sharePDFBinding: Binding<IdentifiableURL?> {
        Binding(
            get: { viewModel.sharePDFURL.map(IdentifiableURL.init) },
            set: { viewModel.sharePDFURL = $0?.url }
        )
    }

    private var printErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.printError != nil },
            set: { if !$0 { viewModel.printError = nil } }
        )
    }

    private var offlineErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.offlineError != nil },
            set: { if !$0 { viewModel.offlineError = nil } }
        )
    }

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(viewModel.statusMessage)
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.isFusing || viewModel.isSavingOffline || viewModel.isGeocodingAddress || viewModel.isBuildingFusedMap {
                    ProgressView()
                        .tint(LiDirtColors.constructionYellow)
                }

                Button {
                    viewModel.openContourMapViewer()
                } label: {
                    Image(systemName: "square.3.layers.3d.down.right")
                        .font(.title3)
                        .foregroundStyle(LiDirtColors.constructionYellow)
                }
                .disabled(!viewModel.canOpenContourMap || viewModel.isBuildingFusedMap)
                .accessibilityLabel("Contour map")

                Button {
                    viewModel.beginJobSiteCropEdit()
                } label: {
                    Image(systemName: "crop.rotate")
                        .font(.title3)
                        .foregroundStyle(LiDirtColors.constructionYellow)
                }
                .accessibilityLabel("Adjust Job Site")

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

    private var cropEditChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(viewModel.statusMessage)
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { viewModel.finishJobSiteCropEdit(save: false) }
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textSecondary)
                Button("Done") { viewModel.finishJobSiteCropEdit(save: true) }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LiDirtColors.gunmetalDeep)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(LiDirtColors.constructionYellow, in: Capsule())
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
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
                    Button {
                        dismiss()
                        viewModel.openContourMapViewer()
                    } label: {
                        Label("Open contour map", systemImage: "square.3.layers.3d.down.right")
                    }
                    .disabled(!viewModel.canOpenContourMap || viewModel.isBuildingFusedMap)
                    Toggle("Fused map only (hide street tiles)", isOn: Binding(
                        get: { viewModel.fusedMapOnly },
                        set: { viewModel.setFusedMapOnly($0) }
                    ))
                    Toggle("Fused surface map", isOn: Binding(
                        get: { viewModel.showFusedSurfaceMap },
                        set: { newValue in
                            viewModel.showFusedSurfaceMap = newValue
                            viewModel.rebuildContours()
                        }
                    ))
                    Text("USGS 3DEP (+ LiDAR when scanned) hillshade + contours. This is what stays sharp when you zoom into a pad — Apple street tiles will look blocky.")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)
                    Toggle("USGS topo tiles", isOn: $viewModel.showTopo)
                        .disabled(viewModel.fusedMapOnly)
                    Toggle("Vector contour lines", isOn: Binding(
                        get: { viewModel.showContours },
                        set: { newValue in
                            viewModel.showContours = newValue
                            viewModel.rebuildContours()
                        }
                    ))
                    Toggle("Building outlines", isOn: Binding(
                        get: { viewModel.showBuildings },
                        set: { viewModel.setShowBuildings($0) }
                    ))
                    Text(viewModel.isLoadingBuildings
                         ? "Loading OpenStreetMap building footprints…"
                         : "Shaded building footprints from OpenStreetMap (where mapped).")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)
                    Toggle("Job Site rectangle", isOn: $viewModel.showJobSiteOverlay)
                }

                Section {
                    Text("Drag, pinch, and twist the yellow frame on the map — like cropping a photo. Sliders below are optional fine-tuning.")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)
                    Button {
                        dismiss()
                        viewModel.beginJobSiteCropEdit()
                    } label: {
                        Label("Adjust on map", systemImage: "crop.rotate")
                    }
                    Toggle("Square (link sides)", isOn: Binding(
                        get: { viewModel.linkSquareSides },
                        set: { viewModel.setLinkSquareSides($0) }
                    ))
                    HStack {
                        Text("Width")
                        Slider(
                            value: Binding(
                                get: { viewModel.outlineWidthFeet },
                                set: { viewModel.updateOutlineWidthFeet($0) }
                            ),
                            in: JobSiteDefaults.minSideFeet...JobSiteDefaults.maxSideFeet,
                            step: 5
                        )
                        Text("\(Int(viewModel.outlineWidthFeet.rounded())) ft")
                            .font(LiDirtTypography.mono)
                            .foregroundStyle(LiDirtColors.constructionYellow)
                            .frame(width: 56, alignment: .trailing)
                    }
                    HStack {
                        Text("Length")
                        Slider(
                            value: Binding(
                                get: { viewModel.outlineLengthFeet },
                                set: { viewModel.updateOutlineLengthFeet($0) }
                            ),
                            in: JobSiteDefaults.minSideFeet...JobSiteDefaults.maxSideFeet,
                            step: 5
                        )
                        .disabled(viewModel.linkSquareSides)
                        Text("\(Int(viewModel.outlineLengthFeet.rounded())) ft")
                            .font(LiDirtTypography.mono)
                            .foregroundStyle(LiDirtColors.constructionYellow)
                            .frame(width: 56, alignment: .trailing)
                    }
                    Text(Self.areaHelp(
                        widthFeet: viewModel.outlineWidthFeet,
                        lengthFeet: viewModel.outlineLengthFeet,
                        rotationDegrees: viewModel.jobSite?.rotationDegrees ?? 0
                    ))
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textMuted)

                    Button("Place outline at map center") {
                        viewModel.placeOutlineAtMapCenter()
                    }
                    Button("Move outline to GPS") {
                        viewModel.moveJobSiteToGPS()
                    }

                    Toggle("Lock view to Job Site", isOn: $viewModel.lockViewToJobSite)
                    Button("Set from current map view") { viewModel.setJobSiteFromCurrentView() }
                    Button("Set from LiDAR scan") { viewModel.setJobSiteFromScan() }
                    Button("Zoom to Job Site") { viewModel.zoomToJobSite() }
                        .disabled(viewModel.jobSite == nil)
                    Button("Clear Job Site", role: .destructive) { viewModel.clearJobSite() }
                        .disabled(viewModel.jobSite == nil)
                } header: {
                    Text("Scan area outline")
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
                            Label(
                                "Download \(Int(viewModel.outlineWidthFeet.rounded()))×\(Int(viewModel.outlineLengthFeet.rounded())) ft topo",
                                systemImage: "arrow.down.circle"
                            )
                        }
                    }
                    .disabled(
                        viewModel.addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || viewModel.projectId == nil
                        || viewModel.isGeocodingAddress
                        || viewModel.isSavingOffline
                    )
                    Text("Uses the outline size above — rectangle or square. LiDAR fuses in when a scan is loaded.")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)
                } header: {
                    Text("Offline topo by address")
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

    private static func areaHelp(widthFeet: Double, lengthFeet: Double, rotationDegrees: Double) -> String {
        let area = widthFeet * lengthFeet
        let rot = rotationDegrees.truncatingRemainder(dividingBy: 360)
        let rotNote = abs(rot) < 0.5 ? "" : String(format: " · %.0f°", rot)
        if area < 1_000 {
            return String(format: "~%.0f×%.0f ft · %.0f sq ft%@", widthFeet, lengthFeet, area, rotNote)
        }
        return String(format: "~%.0f×%.0f ft · %.2g sq ft%@", widthFeet, lengthFeet, area, rotNote)
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

/// Pinch / pan canvas for the rendered contour map (no MapKit tiles).
private struct ContourMapCanvas: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            LiDirtColors.gunmetal
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in lastOffset = offset }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value.magnification, 1), 12)
                        }
                        .onEnded { _ in lastScale = scale }
                )
                .padding(8)
        }
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
        // Prefer topo-looking muted standard underlay only if tiles fail; overlay replaces content.
        map.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        map.setRegion(viewModel.region, animated: false)
        context.coordinator.mapView = map
        context.coordinator.applyBaseMapStyle()
        context.coordinator.applyCameraBoundary()
        context.coordinator.applyOverlays()
        context.coordinator.syncCropEditor()
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.mapView = mapView
        context.coordinator.applyBaseMapStyle()
        context.coordinator.applyCameraBoundary()
        context.coordinator.applyOverlays()
        context.coordinator.syncCropEditor()
        // While cropping, keep the map fixed — only the frame moves.
        if viewModel.isEditingJobSiteCrop { return }
        if abs(mapView.region.center.latitude - viewModel.region.center.latitude) > 1e-5
            || abs(mapView.region.span.latitudeDelta - viewModel.region.span.latitudeDelta) > 1e-6 {
            mapView.setRegion(viewModel.region, animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var viewModel: SiteMapViewModel
        weak var mapView: MKMapView?
        private var topoOverlay: MKTileOverlay?
        private var fusedOverlay: FusedMapGroundOverlay?
        private var lastContourIDs: [String] = []
        private var lastBuildingIDs: [String] = []
        private var lastJobSite: JobSiteBounds?
        private var showingJobSite = false
        private var lastLockedBounds: JobSiteBounds?
        private var lastLockEnabled = false
        private weak var cropEditor: JobSiteCropEditorView?
        private var isCropEditing = false
        private var savedScrollEnabled = true
        private var savedZoomEnabled = true
        private var savedRotateEnabled = true
        private var savedPitchEnabled = true
        private var lastFusedMapOnly: Bool?

        init(viewModel: SiteMapViewModel) {
            self.viewModel = viewModel
        }

        func applyBaseMapStyle() {
            guard let mapView else { return }
            let only = viewModel.fusedMapOnly && viewModel.fusedMapImage != nil
            if lastFusedMapOnly == only { return }
            lastFusedMapOnly = only
            if only {
                // Hide blocky street tiles — contour overlay is the map.
                let config = MKStandardMapConfiguration(emphasisStyle: .muted)
                config.pointOfInterestFilter = .excludingAll
                config.showsTraffic = false
                mapView.preferredConfiguration = config
                mapView.alpha = 1
            } else {
                mapView.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
            }
        }

        func applyCameraBoundary() {
            guard let mapView else { return }
            let shouldLock = !viewModel.isEditingJobSiteCrop
                && viewModel.lockViewToJobSite
                && (viewModel.jobSite?.isValid == true)
            if shouldLock, let jobSite = viewModel.jobSite {
                if !lastLockEnabled || lastLockedBounds != jobSite {
                    mapView.cameraBoundary = MKMapView.CameraBoundary(mapRect: jobSite.mapRect)
                    lastLockedBounds = jobSite
                    lastLockEnabled = true
                }
            } else if lastLockEnabled || mapView.cameraBoundary != nil {
                mapView.cameraBoundary = nil
                lastLockedBounds = nil
                lastLockEnabled = false
            }
        }

        func syncCropEditor() {
            guard let mapView else { return }
            let editing = viewModel.isEditingJobSiteCrop
            if editing {
                if !isCropEditing {
                    isCropEditing = true
                    savedScrollEnabled = mapView.isScrollEnabled
                    savedZoomEnabled = mapView.isZoomEnabled
                    savedRotateEnabled = mapView.isRotateEnabled
                    savedPitchEnabled = mapView.isPitchEnabled
                    mapView.isScrollEnabled = false
                    mapView.isZoomEnabled = false
                    mapView.isRotateEnabled = false
                    mapView.isPitchEnabled = false
                    // Apply the zoomed-out preview region once when entering crop mode.
                    mapView.setRegion(viewModel.region, animated: true)
                }
                if cropEditor == nil, let bounds = viewModel.jobSite {
                    let editor = JobSiteCropEditorView(bounds: bounds)
                    editor.translatesAutoresizingMaskIntoConstraints = false
                    editor.mapView = mapView
                    editor.onBoundsChanged = { [weak self] updated in
                        self?.viewModel.updateJobSiteFromCrop(updated)
                    }
                    mapView.addSubview(editor)
                    NSLayoutConstraint.activate([
                        editor.topAnchor.constraint(equalTo: mapView.topAnchor),
                        editor.bottomAnchor.constraint(equalTo: mapView.bottomAnchor),
                        editor.leadingAnchor.constraint(equalTo: mapView.leadingAnchor),
                        editor.trailingAnchor.constraint(equalTo: mapView.trailingAnchor)
                    ])
                    cropEditor = editor
                }
            } else if isCropEditing {
                isCropEditing = false
                cropEditor?.removeFromSuperview()
                cropEditor = nil
                mapView.isScrollEnabled = savedScrollEnabled
                mapView.isZoomEnabled = savedZoomEnabled
                mapView.isRotateEnabled = savedRotateEnabled
                mapView.isPitchEnabled = savedPitchEnabled
            }
        }

        func applyOverlays() {
            guard let mapView else { return }

            // Prefer the custom fused surface map over USGS print tiles for the Job Site.
            let hasFused = viewModel.showFusedSurfaceMap && viewModel.fusedMapImage != nil
            if viewModel.showTopo, !hasFused, !viewModel.fusedMapOnly {
                if topoOverlay == nil {
                    let overlay = USGSTopoOverlay.makeOverlay()
                    topoOverlay = overlay
                    mapView.addOverlay(overlay, level: .aboveRoads)
                }
            } else if let topoOverlay {
                mapView.removeOverlay(topoOverlay)
                self.topoOverlay = nil
            }

            if hasFused,
               let image = viewModel.fusedMapImage,
               let bounds = viewModel.fusedMapBounds {
                let needsReplace = fusedOverlay == nil
                    || fusedOverlay?.siteBounds != bounds
                    || fusedOverlay?.image !== image
                if needsReplace {
                    if let fusedOverlay {
                        mapView.removeOverlay(fusedOverlay)
                    }
                    let overlay = FusedMapGroundOverlay(image: image, bounds: bounds)
                    fusedOverlay = overlay
                    mapView.addOverlay(overlay, level: .aboveRoads)
                }
            } else if let fusedOverlay {
                mapView.removeOverlay(fusedOverlay)
                self.fusedOverlay = nil
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

            // Live MapKit polygons until the fused surface bakes building shading in.
            let liveIDs: [String] = (viewModel.showBuildings && !hasFused)
                ? viewModel.buildingFootprints.map(\.id)
                : []
            if liveIDs != lastBuildingIDs {
                for overlay in mapView.overlays {
                    if let polygon = overlay as? MKPolygon, polygon.title == "Building" {
                        mapView.removeOverlay(polygon)
                    }
                }
                lastBuildingIDs = liveIDs
                for building in viewModel.buildingFootprints where liveIDs.contains(building.id) {
                    var coords = building.coordinates
                    guard coords.count >= 3 else { continue }
                    let polygon = MKPolygon(coordinates: &coords, count: coords.count)
                    polygon.title = "Building"
                    polygon.subtitle = building.kind
                    mapView.addOverlay(polygon, level: .aboveLabels)
                }
            }

            // During crop edit the UIKit overlay draws the frame; hide the MapKit polygon.
            let job = (!viewModel.isEditingJobSiteCrop && viewModel.showJobSiteOverlay)
                ? viewModel.jobSite : nil
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
            if let fused = overlay as? FusedMapGroundOverlay {
                return FusedMapOverlayRenderer(overlay: fused)
            }
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            if let polygon = overlay as? MKPolygon, polygon.title == "Building" {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = UIColor(red: 0.55, green: 0.62, blue: 0.72, alpha: 0.40)
                renderer.strokeColor = UIColor(red: 0.18, green: 0.28, blue: 0.42, alpha: 0.95)
                renderer.lineWidth = 1.5
                return renderer
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
