import SwiftUI
import simd

struct ScanSessionView: View {
    @StateObject private var viewModel: ScanSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var onFinished: (UUID, HeightmapResult?, QualityMetrics, TimeInterval, [ControlPin], UUID, ScanOrientationSnapshot) -> Void

    init(
        projectId: UUID,
        onFinished: @escaping (UUID, HeightmapResult?, QualityMetrics, TimeInterval, [ControlPin], UUID, ScanOrientationSnapshot) -> Void
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
                onCameraPermissionDenied: { viewModel.showCameraDenied = true },
                onCameraTransform: { transform in
                    viewModel.latestCameraTransform = transform
                }
            )
            .ignoresSafeArea()
            #endif

            VStack(spacing: 0) {
                topHUD
                Spacer()
                if case .countdown(let n) = viewModel.pipeline.passPhase {
                    countdownOverlay(n)
                }
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
        .onDisappear { viewModel.onDisappear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                viewModel.handleBackground()
            }
        }
        .onChange(of: viewModel.didFinish) { _, finished in
            guard finished else { return }
            let metrics = viewModel.completedMetrics ?? QualityMetrics(
                coverageRatio: 0, meanSampleCount: 0, rmsResidualM: 0,
                holeRatio: 1, passCount: viewModel.pipeline.completedPassCount, qualityScore: 0
            )
            onFinished(
                viewModel.scanId,
                viewModel.completedHeightmap,
                metrics,
                viewModel.durationSec,
                viewModel.pipeline.controlPins,
                viewModel.projectId,
                viewModel.completedOrientation
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
                metricChip(title: "Goal area", value: viewModel.areaLabel)
                metricChip(
                    title: "Goal met",
                    value: String(format: "%.0f%%", viewModel.pipeline.goalMetPercent)
                )
                metricChip(
                    title: "Residual",
                    value: String(format: "%.1f cm", viewModel.pipeline.meanResidualM * 100)
                )
            }

            Text(viewModel.phaseHint)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textSecondary)

            Text(viewModel.pipeline.trackingStateDescription)
                .font(LiDirtTypography.caption)
                .foregroundStyle(
                    viewModel.pipeline.isSampling
                    ? LiDirtColors.coverageGood
                    : LiDirtColors.coverageThin
                )

            gpsOrientationBanner

            CoverageLegendView()
        }
        .padding(16)
    }

    private var gpsOrientationBanner: some View {
        let snap = viewModel.orientationService.snapshot
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: snap.frameAlignedToNorth ? "location.north.line.fill" : "location")
                    .foregroundStyle(
                        snap.frameAlignedToNorth
                        ? LiDirtColors.coverageGood
                        : LiDirtColors.constructionYellow
                    )
                Text(viewModel.orientationService.statusMessage)
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textSecondary)
                Spacer(minLength: 0)
                if snap.frameAlignedToNorth {
                    Text("N↑")
                        .font(LiDirtTypography.mono)
                        .foregroundStyle(LiDirtColors.constructionYellow)
                }
            }
            if let lat = snap.latitude, let lon = snap.longitude {
                Text(String(
                    format: "GPS %.5f, %.5f (±%.0f m)",
                    lat,
                    lon,
                    snap.horizontalAccuracyM ?? -1
                ))
                .font(LiDirtTypography.mono)
                .foregroundStyle(LiDirtColors.textMuted)
            }
            if let heading = snap.headingDegrees {
                Text(String(
                    format: "Heading %.0f° (%@)",
                    heading,
                    snap.headingSource
                ))
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
            }
            Text("Phone GPS/compass — approximate, not survey-grade.")
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var bottomHUD: some View {
        VStack(spacing: 12) {
            Text("Field grade estimating. Not a certified survey.")
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)

            passControls

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

    @ViewBuilder
    private var passControls: some View {
        switch viewModel.pipeline.passPhase {
        case .awaitingBegin:
            Button("Begin pass") { viewModel.beginPass() }
                .buttonStyle(LiDirtPrimaryButtonStyle())

        case .countdown:
            Button("Cancel countdown") { viewModel.cancelCountdown() }
                .buttonStyle(LiDirtSecondaryButtonStyle())

        case .sampling:
            HStack(spacing: 10) {
                Button("Pause") { viewModel.pause() }
                    .buttonStyle(LiDirtSecondaryButtonStyle())
                Button("End pass") { viewModel.endPass() }
                    .buttonStyle(LiDirtPrimaryButtonStyle())
            }

        case .paused:
            HStack(spacing: 10) {
                Button("Resume") { viewModel.resume() }
                    .buttonStyle(LiDirtPrimaryButtonStyle())
                Button("End pass") { viewModel.endPass() }
                    .buttonStyle(LiDirtSecondaryButtonStyle())
            }

        case .passEnded:
            Button("Start next pass") { viewModel.startNextPass() }
                .buttonStyle(LiDirtSecondaryButtonStyle())
        }
    }

    private func countdownOverlay(_ n: Int) -> some View {
        Text("\(n)")
            .font(.system(size: 120, weight: .black, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(.black)
            .frame(minWidth: 148, minHeight: 148)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LiDirtColors.constructionYellow)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.black, lineWidth: 4)
            )
            .padding(.bottom, 24)
            .accessibilityLabel("Starting in \(n)")
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
