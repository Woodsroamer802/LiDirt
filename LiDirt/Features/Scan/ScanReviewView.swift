import SwiftUI
import UIKit

struct ScanReviewView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let scanId: UUID
    let projectId: UUID
    let heightmap: HeightmapResult?
    let metrics: QualityMetrics
    let durationSec: TimeInterval
    let controlPins: [ControlPin]
    let preferredContourIntervalInches: Double
    var preferredContourSurfaceMode: ContourSurfaceMode = .smoothedGround
    var projectName: String = "Scan"
    var orientation: ScanOrientationSnapshot = .unavailable
    var onContourIntervalChange: ((Double) -> Void)?
    var onContourSurfaceModeChange: ((ContourSurfaceMode) -> Void)?

    var onUpload: () -> Void
    var onRescan: () -> Void
    var onUploadAnyway: () -> Void
    var onDelete: (() -> Void)?

    @State private var showLowCoverageConfirm = false
    @State private var showContours = true
    @State private var showDeleteConfirm = false
    @State private var showTopoMap = false
    @State private var intervalText: String = ""
    @State private var activeIntervalInches: Double = ContourPreview.defaultIntervalInches
    @State private var surfaceMode: ContourSurfaceMode = .smoothedGround

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                scoreHeader
                heightmapSection
                orientationSection
                metricsGrid
                Text(ScanPackageWriter.disclaimer)
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textMuted)
                actions
            }
            .padding(20)
        }
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .navigationTitle("Scan review")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            activeIntervalInches = preferredContourIntervalInches
            intervalText = String(format: "%g", preferredContourIntervalInches)
            surfaceMode = preferredContourSurfaceMode
        }
        .sheet(isPresented: $showTopoMap) {
            NavigationStack {
                SiteMapView(
                    projectName: projectName,
                    projectId: projectId,
                    heightmap: heightmap,
                    orientation: orientation,
                    contourIntervalInches: activeIntervalInches,
                    contourSurfaceMode: surfaceMode,
                    jobSite: environment.projectStore.project(id: projectId)?.jobSite,
                    initialAddress: environment.projectStore.project(id: projectId)?.address,
                    onIntervalChange: { value in
                        activeIntervalInches = value
                        intervalText = String(format: "%g", value)
                        onContourIntervalChange?(value)
                    },
                    onSurfaceModeChange: { mode in
                        surfaceMode = mode
                        onContourSurfaceModeChange?(mode)
                    },
                    onJobSiteChange: { bounds in
                        guard var updated = environment.projectStore.project(id: projectId) else { return }
                        updated.jobSite = bounds
                        environment.projectStore.update(updated)
                    }
                )
            }
        }
        .toolbar {
            if onDelete != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .alert("Coverage low", isPresented: $showLowCoverageConfirm) {
            Button("Rescan thin areas", role: .cancel, action: onRescan)
            Button("Upload anyway", role: .destructive, action: onUploadAnyway)
        } message: {
            Text("Coverage low (score < 50). Rescan thin areas? You can upload anyway for field records.")
        }
        .alert("Delete this scan?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete?() }
        } message: {
            Text("Removes the local scan package and project list entry. This cannot be undone.")
        }
    }

    private var scoreHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quality score")
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(metrics.qualityScore)")
                    .font(LiDirtTypography.score)
                    .foregroundStyle(LiDirtColors.constructionYellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text(metrics.label)
                        .font(LiDirtTypography.headline)
                        .foregroundStyle(LiDirtColors.textPrimary)
                    Text("Averaged LiDAR grade for cut/fill planning")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textSecondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LiDirtColors.gunmetalElevated, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var heightmapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Heightmap preview")
                    .font(LiDirtTypography.headline)
                    .foregroundStyle(LiDirtColors.textPrimary)
                Spacer()
                if orientation.frameAlignedToNorth {
                    Text("N↑")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.constructionYellow)
                }
                Toggle("Contours", isOn: $showContours)
                    .labelsHidden()
                    .tint(LiDirtColors.constructionYellow)
            }

            Picker("Ground detail", selection: $surfaceMode) {
                ForEach(ContourSurfaceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: surfaceMode) { _, mode in
                onContourSurfaceModeChange?(mode)
            }
            Text(surfaceMode.shortHelp)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)

            HStack(spacing: 8) {
                Text("Interval (in)")
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textMuted)
                TextField("0.125", text: $intervalText)
                    .keyboardType(.decimalPad)
                    .font(LiDirtTypography.mono)
                    .foregroundStyle(LiDirtColors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(LiDirtColors.gunmetalDeep, in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: 100)
                Button("Apply") {
                    applyInterval()
                }
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.gunmetalDeep)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(LiDirtColors.constructionYellow, in: RoundedRectangle(cornerRadius: 8))
            }

            ZStack {
                if let heightmap, let cgImage = HeightmapPreviewImage.cgImage(from: heightmap) {
                    Image(uiImage: UIImage(cgImage: cgImage))
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(CGFloat(heightmap.width) / CGFloat(max(heightmap.height, 1)), contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if showContours {
                        ContourPreviewCanvas(
                            heightmap: DEMGroundSmoother.prepareForContours(heightmap, mode: surfaceMode),
                            intervalInches: activeIntervalInches
                        )
                        .aspectRatio(CGFloat(heightmap.width) / CGFloat(max(heightmap.height, 1)), contentMode: .fit)
                        .allowsHitTesting(false)
                    }
                } else {
                    Text("No DEM cells met the minimum sample count. Rescan the pad.")
                        .font(LiDirtTypography.body)
                        .foregroundStyle(LiDirtColors.textSecondary)
                        .padding()
                        .frame(maxWidth: .infinity, minHeight: 160)
                        .background(LiDirtColors.gunmetalElevated, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            if heightmap != nil {
                Button {
                    applyInterval()
                    showTopoMap = true
                } label: {
                    Label("Open Job Site map", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LiDirtSecondaryButtonStyle())
            }

            Text("Type a contour interval (inches). Job Site map uses USGS 3DEP as foundation plus this LiDAR DEM. Green cells met the sample goal (≥\(CoverageGoals.samplesForGoalMet)).")
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
        }
    }

    private func applyInterval() {
        let cleaned = intervalText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else {
            intervalText = String(format: "%g", activeIntervalInches)
            return
        }
        activeIntervalInches = max(value, 0.01)
        intervalText = String(format: "%g", activeIntervalInches)
        onContourIntervalChange?(activeIntervalInches)
    }

    private var orientationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Location & orientation")
                .font(LiDirtTypography.headline)
                .foregroundStyle(LiDirtColors.textPrimary)
            Text(orientation.frameAlignedToNorth
                 ? "Heightmap aligned using phone GPS + compass (prefer true north)."
                 : "Local AR frame (north align unavailable or denied).")
                .font(LiDirtTypography.body)
                .foregroundStyle(LiDirtColors.textSecondary)
            if let lat = orientation.latitude, let lon = orientation.longitude {
                Text(String(
                    format: "GPS %.5f, %.5f (±%.0f m)",
                    lat,
                    lon,
                    orientation.horizontalAccuracyM ?? -1
                ))
                .font(LiDirtTypography.mono)
                .foregroundStyle(LiDirtColors.textMuted)
            }
            if let heading = orientation.headingDegrees {
                Text(String(format: "Heading %.0f° (%@)", heading, orientation.headingSource))
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textMuted)
            }
            Text(orientation.disclaimer)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LiDirtColors.gunmetalElevated, in: RoundedRectangle(cornerRadius: 10))
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricTile("Coverage", String(format: "%.0f%%", metrics.coverageRatio * 100))
            metricTile("Holes", String(format: "%.0f%%", metrics.holeRatio * 100))
            metricTile("Mean samples", String(format: "%.1f", metrics.meanSampleCount))
            metricTile("RMS residual", String(format: "%.1f cm", metrics.rmsResidualM * 100))
            metricTile("Passes", "\(metrics.passCount)")
            metricTile("Duration", formatDuration(durationSec))
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button("Upload") {
                if metrics.blocksUploadByDefault {
                    showLowCoverageConfirm = true
                } else {
                    onUpload()
                }
            }
            .buttonStyle(LiDirtPrimaryButtonStyle())

            Button("Rescan", action: onRescan)
                .buttonStyle(LiDirtSecondaryButtonStyle())

            if onDelete != nil {
                Button("Delete scan", role: .destructive) {
                    showDeleteConfirm = true
                }
                .buttonStyle(LiDirtSecondaryButtonStyle())
            }
        }
    }

    private func metricTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
            Text(value)
                .font(LiDirtTypography.headline)
                .foregroundStyle(LiDirtColors.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LiDirtColors.gunmetalElevated, in: RoundedRectangle(cornerRadius: 10))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
