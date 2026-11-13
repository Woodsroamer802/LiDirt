import SwiftUI
import UIKit

struct ScanReviewView: View {
    let scanId: UUID
    let projectId: UUID
    let heightmap: HeightmapResult?
    let metrics: QualityMetrics
    let durationSec: TimeInterval
    let controlPins: [ControlPin]
    let preferredContourIntervalInches: Double

    var onUpload: () -> Void
    var onRescan: () -> Void
    var onUploadAnyway: () -> Void

    @State private var showLowCoverageConfirm = false
    @State private var showContours = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                scoreHeader
                heightmapSection
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
        .alert("Coverage low", isPresented: $showLowCoverageConfirm) {
            Button("Rescan thin areas", role: .cancel, action: onRescan)
            Button("Upload anyway", role: .destructive, action: onUploadAnyway)
        } message: {
            Text("Coverage low (score < 50). Rescan thin areas? You can upload anyway for field records.")
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
                Toggle("Contours", isOn: $showContours)
                    .labelsHidden()
                    .tint(LiDirtColors.constructionYellow)
                Text("1/8 in")
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textMuted)
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
                            heightmap: heightmap,
                            intervalInches: preferredContourIntervalInches
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

            Text("Contour intervals down to 1/8 inch on the smoothed surface (display only).")
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
        }
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
