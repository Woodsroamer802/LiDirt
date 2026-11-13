import SwiftUI

struct ScanSessionView: View {
    @StateObject private var viewModel: ScanSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var onFinished: (UUID, HeightmapResult?, QualityMetrics, TimeInterval, [ControlPin], UUID) -> Void

    init(
        projectId: UUID,
        onFinished: @escaping (UUID, HeightmapResult?, QualityMetrics, TimeInterval, [ControlPin], UUID) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ScanSessionViewModel(projectId: projectId))
        self.onFinished = onFinished
    }

    var body: some View {
        ZStack {
            #if targetEnvironment(simulator)
            simulatorPlaceholder
            #else
            ARScanView(
                pipeline: viewModel.pipeline,
                onCameraPermissionDenied: { viewModel.showCameraDenied = true }
            )
            .ignoresSafeArea()
            #endif

            VStack(spacing: 0) {
                topHUD
                Spacer()
                if viewModel.pipeline.thermalWarning {
                    Text("Device warm; quality may drop.")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.gunmetalDeep)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(LiDirtColors.constructionYellow, in: Capsule())
                        .padding(.bottom, 8)
                }
                bottomHUD
            }
        }
        .onAppear { viewModel.onAppear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                viewModel.handleBackground()
            }
        }
        .onChange(of: viewModel.didFinish) { _, finished in
            guard finished else { return }
            let metrics = viewModel.completedMetrics ?? QualityMetrics(
                coverageRatio: 0, meanSampleCount: 0, rmsResidualM: 0,
                holeRatio: 1, passCount: viewModel.pipeline.passCount, qualityScore: 0
            )
            onFinished(
                viewModel.scanId,
                viewModel.completedHeightmap,
                metrics,
                viewModel.durationSec,
                viewModel.pipeline.controlPins,
                viewModel.projectId
            )
        }
        .alert("Camera access needed", isPresented: $viewModel.showCameraDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text("LiDirt needs the camera for LiDAR scene reconstruction. Enable camera access in Settings.")
        }
        .statusBarHidden(true)
    }

    private var topHUD: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(LiDirtColors.textPrimary)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                Text(viewModel.passLabel)
                    .font(LiDirtTypography.headline)
                    .foregroundStyle(LiDirtColors.constructionYellow)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            HStack(spacing: 16) {
                metricChip(title: "Area", value: viewModel.areaLabel)
                metricChip(
                    title: "Cells",
                    value: String(format: "%.0f%%", viewModel.pipeline.cellsFilledPercent)
                )
                metricChip(
                    title: "Residual",
                    value: String(format: "%.1f cm", viewModel.pipeline.meanResidualM * 100)
                )
            }

            Text(viewModel.pipeline.trackingStateDescription)
                .font(LiDirtTypography.caption)
                .foregroundStyle(
                    viewModel.pipeline.isSampling
                    ? LiDirtColors.coverageGood
                    : LiDirtColors.coverageThin
                )

            CoverageLegendView()
        }
        .padding(16)
    }

    private var bottomHUD: some View {
        VStack(spacing: 12) {
            Text("Field grade estimating. Not a certified survey.")
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)

            HStack(spacing: 10) {
                if viewModel.pipeline.isPaused || !viewModel.pipeline.isSampling {
                    Button("Resume") { viewModel.resume() }
                        .buttonStyle(LiDirtPrimaryButtonStyle())
                } else {
                    Button("Pause") { viewModel.pause() }
                        .buttonStyle(LiDirtSecondaryButtonStyle())
                }

                Button("Next pass") { viewModel.nextPass() }
                    .buttonStyle(LiDirtSecondaryButtonStyle())
            }

            HStack(spacing: 10) {
                Button("Mark pin") { viewModel.markPin() }
                    .buttonStyle(LiDirtSecondaryButtonStyle())
                Button("Finish scan") { viewModel.finish() }
                    .buttonStyle(LiDirtPrimaryButtonStyle())
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [LiDirtColors.gunmetalDeep.opacity(0), LiDirtColors.gunmetalDeep.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
            Text(value)
                .font(LiDirtTypography.mono)
                .foregroundStyle(LiDirtColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    #if targetEnvironment(simulator)
    private var simulatorPlaceholder: some View {
        ZStack {
            LiDirtColors.gunmetalDeep.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Simulator — no LiDAR")
                    .font(LiDirtTypography.title)
                    .foregroundStyle(LiDirtColors.constructionYellow)
                Text("ScanSession is blocked on non-LiDAR hardware. Use a LiDAR Pro device for capture. Unit tests cover DEM averaging and quality scoring without ARKit.")
                    .font(LiDirtTypography.body)
                    .foregroundStyle(LiDirtColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }
    #endif
}
