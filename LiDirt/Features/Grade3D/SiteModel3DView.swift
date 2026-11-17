import SwiftUI
import SceneKit

/// Interactive 3D proposed-grade viewer: DEM mesh + finished-work cutouts + shape flags.
struct SiteModel3DView: View {
    @StateObject private var viewModel: SiteModel3DViewModel
    @Environment(\.dismiss) private var dismiss

    init(heightmap: HeightmapResult) {
        _viewModel = StateObject(wrappedValue: SiteModel3DViewModel(heightmap: heightmap))
    }

    var body: some View {
        VStack(spacing: 0) {
            SceneKitTerrainView(
                heightmap: viewModel.displayHeightmap,
                cutouts: viewModel.cutouts,
                flags: viewModel.flaggedShape.flags,
                selectedFlagId: viewModel.selectedFlagId
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LiDirtColors.gunmetalDeep)

            controlPanel
        }
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .navigationTitle("3D grade model")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
                    .foregroundStyle(LiDirtColors.constructionYellow)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $viewModel.showProposed) {
                    Text(viewModel.showProposed ? "Proposed" : "Existing")
                }
                .toggleStyle(.button)
                .tint(LiDirtColors.constructionYellow)
                .onChange(of: viewModel.showProposed) { _, _ in }
            }
        }
    }

    private var controlPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(viewModel.statusMessage)
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textSecondary)
                Text(viewModel.volumeSummary)
                    .font(LiDirtTypography.mono)
                    .foregroundStyle(LiDirtColors.constructionYellow)

                presetsSection
                if viewModel.selectedCutout != nil {
                    cutoutEditSection
                }
                flagsSection
            }
            .padding(16)
        }
        .frame(maxHeight: 340)
        .background(LiDirtColors.gunmetalElevated)
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Finished work")
                .font(LiDirtTypography.headline)
                .foregroundStyle(LiDirtColors.textPrimary)
            Text("Place a shape to show the customer how the pad / dig will look.")
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(FinishWorkPreset.allCases.filter { $0 != .custom }) { preset in
                    Button {
                        viewModel.addPreset(preset)
                    } label: {
                        Text(preset.displayName)
                            .font(LiDirtTypography.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(LiDirtSecondaryButtonStyle())
                }
            }

            if !viewModel.cutouts.isEmpty {
                HStack {
                    Button("Clear shapes", role: .destructive) {
                        viewModel.clearAllCutouts()
                    }
                    .font(LiDirtTypography.caption)
                    Spacer()
                }
            }
        }
    }

    private var cutoutEditSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected shape")
                .font(LiDirtTypography.headline)
                .foregroundStyle(LiDirtColors.textPrimary)

            HStack(spacing: 8) {
                draftField("W ft", text: $viewModel.draftWidthFeet)
                draftField("L ft", text: $viewModel.draftLengthFeet)
                draftField("Depth ft", text: $viewModel.draftDepthFeet)
            }
            Button("Apply sizes") { viewModel.applyDraftToSelected() }
                .buttonStyle(LiDirtPrimaryButtonStyle())

            HStack(spacing: 8) {
                nudgeButton("N") { viewModel.nudgeSelected(dxFeet: 0, dzFeet: -3) }
                nudgeButton("S") { viewModel.nudgeSelected(dxFeet: 0, dzFeet: 3) }
                nudgeButton("W") { viewModel.nudgeSelected(dxFeet: -3, dzFeet: 0) }
                nudgeButton("E") { viewModel.nudgeSelected(dxFeet: 3, dzFeet: 0) }
                Spacer()
                Button("Delete", role: .destructive) { viewModel.deleteSelectedCutout() }
                    .font(LiDirtTypography.caption)
            }
        }
    }

    private var flagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shape flags")
                .font(LiDirtTypography.headline)
                .foregroundStyle(LiDirtColors.textPrimary)
            Text("Map complicated outlines: drop flags at corners, then enter taped feet between opposite flags.")
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)

            HStack(spacing: 8) {
                Button("Add flag") { viewModel.addFlagAtCenter() }
                    .buttonStyle(LiDirtSecondaryButtonStyle())
                Button("Suggest opposites") { viewModel.suggestOppositeMeasurements() }
                    .buttonStyle(LiDirtSecondaryButtonStyle())
            }

            if !viewModel.flaggedShape.flags.isEmpty {
                ForEach(viewModel.flaggedShape.flags) { flag in
                    Button {
                        viewModel.selectedFlagId = flag.id
                    } label: {
                        HStack {
                            Text("Flag \(flag.label)")
                                .foregroundStyle(
                                    viewModel.selectedFlagId == flag.id
                                        ? LiDirtColors.constructionYellow
                                        : LiDirtColors.textPrimary
                                )
                            Spacer()
                            Text(String(format: "%.1f, %.1f m", flag.localX, flag.localZ))
                                .font(LiDirtTypography.mono)
                                .foregroundStyle(LiDirtColors.textMuted)
                        }
                    }
                }

                if viewModel.selectedFlagId != nil {
                    HStack(spacing: 8) {
                        nudgeButton("N") { viewModel.nudgeSelectedFlag(dxFeet: 0, dzFeet: -3) }
                        nudgeButton("S") { viewModel.nudgeSelectedFlag(dxFeet: 0, dzFeet: 3) }
                        nudgeButton("W") { viewModel.nudgeSelectedFlag(dxFeet: -3, dzFeet: 0) }
                        nudgeButton("E") { viewModel.nudgeSelectedFlag(dxFeet: 3, dzFeet: 0) }
                        Spacer()
                        Button("Delete flag", role: .destructive) { viewModel.deleteSelectedFlag() }
                            .font(LiDirtTypography.caption)
                    }
                }
            }

            if viewModel.flaggedShape.flags.count >= 2 {
                Text("Opposite-flag measurement")
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textSecondary)

                HStack {
                    Picker("From", selection: $viewModel.measureFromFlagId) {
                        Text("From").tag(UUID?.none)
                        ForEach(viewModel.flaggedShape.flags) { f in
                            Text(f.label).tag(Optional(f.id))
                        }
                    }
                    Picker("To", selection: $viewModel.measureToFlagId) {
                        Text("To").tag(UUID?.none)
                        ForEach(viewModel.flaggedShape.flags) { f in
                            Text(f.label).tag(Optional(f.id))
                        }
                    }
                    draftField("ft", text: $viewModel.draftMeasuredFeet)
                }

                HStack(spacing: 8) {
                    Button("Save measurement") { viewModel.addOrUpdateMeasurement() }
                        .buttonStyle(LiDirtPrimaryButtonStyle())
                    Button("Fit to tape") { viewModel.fitFlagsToOppositeMeasurements() }
                        .buttonStyle(LiDirtSecondaryButtonStyle())
                }

                ForEach(viewModel.flaggedShape.measurements) { m in
                    let from = viewModel.flaggedShape.flags.first { $0.id == m.fromFlagId }?.label ?? "?"
                    let to = viewModel.flaggedShape.flags.first { $0.id == m.toFlagId }?.label ?? "?"
                    Text(String(format: "%@ ↔ %@ · %.2f ft (%@)", from, to, m.measuredFeet, m.kind.displayName))
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)
                }
            }
        }
    }

    private func draftField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .padding(8)
                .background(LiDirtColors.gunmetalDeep, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(LiDirtColors.textPrimary)
        }
    }

    private func nudgeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(LiDirtTypography.caption)
            .frame(width: 36, height: 36)
            .background(LiDirtColors.gunmetalDeep, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(LiDirtColors.constructionYellow)
    }
}

// MARK: - SceneKit host

private struct SceneKitTerrainView: UIViewRepresentable {
    var heightmap: HeightmapResult
    var cutouts: [GradeCutout]
    var flags: [ShapeFlag]
    var selectedFlagId: UUID?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1)
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = true
        context.coordinator.rebuild(on: view, heightmap: heightmap, cutouts: cutouts, flags: flags, selectedFlagId: selectedFlagId)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.rebuild(
            on: uiView,
            heightmap: heightmap,
            cutouts: cutouts,
            flags: flags,
            selectedFlagId: selectedFlagId
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var lastSignature: String = ""

        func rebuild(
            on view: SCNView,
            heightmap: HeightmapResult,
            cutouts: [GradeCutout],
            flags: [ShapeFlag],
            selectedFlagId: UUID?
        ) {
            let signature = "\(heightmap.width)x\(heightmap.height)-\(heightmap.bounds.minY)-\(heightmap.bounds.maxY)-\(cutouts.count)-\(flags.count)-\(selectedFlagId?.uuidString ?? "")-\(cutouts.map(\.id.uuidString).joined())"
            // Always refresh when proposed elevations change — include elev checksum.
            let elevHash = heightmap.elevations.reduce(into: 0 as UInt64) { partial, v in
                guard !v.isNaN else { return }
                partial = partial &* 1_000_003 &+ UInt64(v.bitPattern)
            }
            let full = signature + "-\(elevHash)"
            guard full != lastSignature else { return }
            lastSignature = full

            let scene = SCNScene()
            if let geometry = TerrainMeshBuilder.makeGeometry(heightmap: heightmap) {
                let node = SCNNode(geometry: geometry)
                scene.rootNode.addChildNode(node)
            }

            for cutout in cutouts {
                scene.rootNode.addChildNode(Self.cutoutOutlineNode(cutout, heightmap: heightmap))
            }
            for flag in flags {
                scene.rootNode.addChildNode(
                    Self.flagNode(flag, selected: flag.id == selectedFlagId, heightmap: heightmap)
                )
            }

            let cx = Float(heightmap.originX + Double(heightmap.width) * heightmap.cellSizeM * 0.5)
            let cz = Float(heightmap.originZ + Double(heightmap.height) * heightmap.cellSizeM * 0.5)
            let cy = Float((heightmap.bounds.minY + heightmap.bounds.maxY) * 0.5)
            let span = Float(max(heightmap.bounds.maxX - heightmap.bounds.minX, heightmap.bounds.maxZ - heightmap.bounds.minZ))

            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 45
            camera.position = SCNVector3(cx + span * 0.8, cy + span * 0.7, cz + span * 0.8)
            camera.look(at: SCNVector3(cx, cy, cz))
            scene.rootNode.addChildNode(camera)

            let light = SCNNode()
            light.light = SCNLight()
            light.light?.type = .directional
            light.light?.intensity = 800
            light.eulerAngles = SCNVector3(-0.9, 0.4, 0)
            scene.rootNode.addChildNode(light)

            view.scene = scene
            view.pointOfView = camera
        }

        private static func cutoutOutlineNode(_ cutout: GradeCutout, heightmap: HeightmapResult) -> SCNNode {
            let y = Float(heightmap.bounds.maxY + 0.15)
            let parent = SCNNode()
            let color = UIColor(red: 0.96, green: 0.78, blue: 0.12, alpha: 1)

            switch cutout.shape {
            case .circle:
                let radius = CGFloat(cutout.widthM * 0.5)
                let path = UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
                let shape = SCNShape(path: path, extrusionDepth: 0.05)
                shape.firstMaterial?.diffuse.contents = color
                let node = SCNNode(geometry: shape)
                node.position = SCNVector3(Float(cutout.centerLocalX), y, Float(cutout.centerLocalZ))
                node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
                parent.addChildNode(node)
            case .rectangle:
                let w = CGFloat(cutout.widthM)
                let l = CGFloat(cutout.lengthM)
                let path = UIBezierPath(rect: CGRect(x: -w / 2, y: -l / 2, width: w, height: l))
                let shape = SCNShape(path: path, extrusionDepth: 0.05)
                shape.firstMaterial?.diffuse.contents = color
                let node = SCNNode(geometry: shape)
                node.position = SCNVector3(Float(cutout.centerLocalX), y, Float(cutout.centerLocalZ))
                node.eulerAngles = SCNVector3(-Float.pi / 2, Float(cutout.rotationDegrees * .pi / 180), 0)
                parent.addChildNode(node)
            }
            return parent
        }

        private static func flagNode(_ flag: ShapeFlag, selected: Bool, heightmap: HeightmapResult) -> SCNNode {
            let pole = SCNCylinder(radius: 0.05, height: 1.2)
            pole.firstMaterial?.diffuse.contents = selected
                ? UIColor(red: 0.96, green: 0.78, blue: 0.12, alpha: 1)
                : UIColor(red: 0.85, green: 0.30, blue: 0.28, alpha: 1)
            let node = SCNNode(geometry: pole)
            let y = Float(max(flag.localY, heightmap.bounds.minY)) + 0.6
            node.position = SCNVector3(Float(flag.localX), y, Float(flag.localZ))

            let text = SCNText(string: flag.label, extrusionDepth: 0.02)
            text.font = UIFont.boldSystemFont(ofSize: 0.35)
            text.firstMaterial?.diffuse.contents = UIColor.white
            let label = SCNNode(geometry: text)
            label.position = SCNVector3(-0.1, 0.7, 0)
            label.scale = SCNVector3(0.5, 0.5, 0.5)
            node.addChildNode(label)
            return node
        }
    }
}
