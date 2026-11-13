import SwiftUI

struct UploadStatusView: View {
    @ObservedObject var queue: UploadQueue
    var scanId: UUID
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Upload")
                .font(LiDirtTypography.title)
                .foregroundStyle(LiDirtColors.textPrimary)

            if let item = queue.items.first(where: { $0.id == scanId }) {
                statusRow(item)

                if item.status == .failed {
                    Text(item.lastError ?? "Upload failed")
                        .font(LiDirtTypography.body)
                        .foregroundStyle(LiDirtColors.danger)
                    Button("Retry") {
                        Task { await queue.retry(scanId) }
                    }
                    .buttonStyle(LiDirtPrimaryButtonStyle())
                }

                if item.status == .queued || item.status == .uploading {
                    ProgressView()
                        .tint(LiDirtColors.constructionYellow)
                    Text(item.status == .uploading
                         ? "Uploading heightmap + metadata…"
                         : "Queued — will retry when online.")
                        .font(LiDirtTypography.body)
                        .foregroundStyle(LiDirtColors.textSecondary)
                }

                if item.status == .accepted {
                    Text("Accepted. Package stored for processing.")
                        .font(LiDirtTypography.body)
                        .foregroundStyle(LiDirtColors.coverageGood)
                    Button("Done", action: onDone)
                        .buttonStyle(LiDirtPrimaryButtonStyle())
                }
            } else {
                Text("Preparing package…")
                    .foregroundStyle(LiDirtColors.textSecondary)
                ProgressView()
                    .tint(LiDirtColors.constructionYellow)
            }

            Text("Offline packages stay in Application Support/UploadsQueue until accepted.")
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)

            Spacer()
        }
        .padding(24)
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .task {
            await queue.processAll()
        }
    }

    private func statusRow(_ item: QueuedUpload) -> some View {
        HStack {
            Text(statusLabel(item.status))
                .font(LiDirtTypography.headline)
                .foregroundStyle(LiDirtColors.constructionYellow)
            Spacer()
            Text("Attempts \(item.attemptCount)")
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
        }
        .padding(14)
        .background(LiDirtColors.gunmetalElevated, in: RoundedRectangle(cornerRadius: 10))
    }

    private func statusLabel(_ status: ScanUploadStatus) -> String {
        switch status {
        case .localOnly: return "Local only"
        case .queued: return "Queued"
        case .uploading: return "Uploading"
        case .accepted: return "Accepted"
        case .failed: return "Failed"
        }
    }
}
