import SwiftUI

/// Workspace “3D Models” tab — scan DEMs ready for proposed-grade editing (Figma Make section).
struct ModelsListView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var activeModel: ActiveSiteModel?
    @State private var loadError: String?

    private var modelRows: [SiteModelRow] {
        var rows: [SiteModelRow] = []
        for project in environment.projectStore.projects {
            for scan in project.scanSummaries.sorted(by: { $0.capturedAt > $1.capturedAt }) {
                rows.append(
                    SiteModelRow(
                        id: scan.id,
                        projectId: project.id,
                        projectName: project.name,
                        projectAddress: project.address,
                        scan: scan
                    )
                )
            }
        }
        return rows.sorted { $0.scan.capturedAt > $1.scan.capturedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WORKSPACE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(LiDirtColors.textMuted)
                    Text("Review point clouds, contours, and proposed finish grades.")
                        .font(LiDirtTypography.body)
                        .foregroundStyle(LiDirtColors.textMuted)
                }

                if modelRows.isEmpty {
                    emptyState
                } else {
                    ForEach(modelRows) { row in
                        Button {
                            openModel(row)
                        } label: {
                            modelRowLabel(row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .navigationTitle("3D Models")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $activeModel) { model in
            NavigationStack {
                SiteModel3DView(heightmap: model.heightmap)
            }
        }
        .alert("Couldn’t open model", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("OK", role: .cancel) { loadError = nil }
        } message: {
            Text(loadError ?? "Unknown error.")
        }
        .task {
            await environment.syncFromCloud()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 44))
                .foregroundStyle(LiDirtColors.constructionYellow)
            Text("3D Models workspace")
                .font(LiDirtTypography.headline)
                .foregroundStyle(LiDirtColors.textPrimary)
            Text("Finish a field scan to create your first model, then place slab / pool cutouts and check materials.")
                .font(LiDirtTypography.body)
                .foregroundStyle(LiDirtColors.textMuted)
                .multilineTextAlignment(.center)
            Text("Use the Projects tab to start a scan.")
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textSecondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(panelBackground)
    }

    private func modelRowLabel(_ row: SiteModelRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LiDirtColors.gunmetalDeep)
                    .frame(width: 48, height: 48)
                Image(systemName: "cube.transparent")
                    .foregroundStyle(LiDirtColors.constructionYellow)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.projectName)
                    .font(LiDirtTypography.headline)
                    .foregroundStyle(LiDirtColors.textPrimary)
                Text(row.scan.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textMuted)
                HStack(spacing: 8) {
                    if let score = row.scan.qualityScore {
                        Text("Score \(score)")
                    }
                    Text(row.scan.uploadStatus.rawValue)
                    if row.scan.localPackagePath == nil {
                        Text("Needs package")
                            .foregroundStyle(LiDirtColors.coverageThin)
                    } else {
                        Text("Open 3D")
                            .foregroundStyle(LiDirtColors.constructionYellow)
                    }
                }
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiDirtColors.textMuted)
        }
        .padding(14)
        .background(panelBackground)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LiDirtColors.gunmetalElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LiDirtColors.hairline, lineWidth: 1)
            )
    }

    private func openModel(_ row: SiteModelRow) {
        let dir: URL
        if let path = row.scan.localPackagePath {
            dir = URL(fileURLWithPath: path)
        } else {
            dir = environment.localScanStore.packageURL(for: row.scan.id)
        }
        guard let loaded = try? ScanPackageReader.load(from: dir) else {
            loadError = "No saved package for this scan yet. Open the project, Finish a scan, wait until the package saves, then try again."
            return
        }
        activeModel = ActiveSiteModel(
            id: row.scan.id,
            projectName: row.projectName,
            heightmap: loaded.heightmap
        )
    }
}

private struct SiteModelRow: Identifiable {
    var id: UUID
    var projectId: UUID
    var projectName: String
    var projectAddress: String?
    var scan: ScanSummary
}

private struct ActiveSiteModel: Identifiable {
    var id: UUID
    var projectName: String
    var heightmap: HeightmapResult
}
