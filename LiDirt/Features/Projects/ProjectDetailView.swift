import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let projectId: UUID

    @State private var showScan = false
    @State private var showUnsupported = false
    @State private var reviewPayload: ReviewPayload?
    @State private var uploadSheet: UploadSheetToken?
    @State private var uploadErrorMessage: String?
    @State private var pendingDelete: ScanSummary?
    @State private var showDeleteConfirm = false
    @State private var showDeleteProjectConfirm = false
    @State private var showSiteMap = false
    @State private var siteMapHeightmap: HeightmapResult?
    @State private var siteMapOrientation: ScanOrientationSnapshot = .unavailable
    @Environment(\.dismiss) private var dismiss

    private var project: Project? {
        environment.projectStore.project(id: projectId)
    }

    var body: some View {
        Group {
            if let project {
                content(project)
            } else {
                Text("Project not found")
                    .foregroundStyle(LiDirtColors.textSecondary)
            }
        }
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .navigationTitle(project?.name ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete project", role: .destructive) {
                    showDeleteProjectConfirm = true
                }
            }
        }
        .sheet(isPresented: $showSiteMap) {
            NavigationStack {
                SiteMapView(
                    heightmap: siteMapHeightmap,
                    orientation: siteMapOrientation,
                    contourIntervalInches: environment.preferredContourIntervalInches,
                    onIntervalChange: { environment.savePreferredContourIntervalInches($0) }
                )
            }
        }
        .fullScreenCover(isPresented: $showScan) {
            ScanSessionView(projectId: projectId) { scanId, heightmap, metrics, duration, pins, projectId, orientation in
                showScan = false
                let summary = ScanSummary(
                    id: scanId,
                    projectId: projectId,
                    qualityScore: metrics.qualityScore,
                    coverageRatio: metrics.coverageRatio,
                    passCount: metrics.passCount,
                    uploadStatus: .localOnly,
                    localPackagePath: nil
                )
                if environment.projectStore.project(id: projectId)?.scanSummaries.contains(where: { $0.id == scanId }) != true {
                    environment.projectStore.addScanSummary(summary)
                }
                reviewPayload = ReviewPayload(
                    scanId: scanId,
                    projectId: projectId,
                    heightmap: heightmap,
                    metrics: metrics,
                    durationSec: duration,
                    controlPins: pins,
                    orientation: orientation
                )
            }
        }
        .navigationDestination(item: $reviewPayload) { payload in
            ScanReviewView(
                scanId: payload.scanId,
                projectId: payload.projectId,
                heightmap: payload.heightmap,
                metrics: payload.metrics,
                durationSec: payload.durationSec,
                controlPins: payload.controlPins,
                preferredContourIntervalInches: environment.preferredContourIntervalInches,
                orientation: payload.orientation,
                onContourIntervalChange: { environment.savePreferredContourIntervalInches($0) },
                onUpload: { beginUpload(payload, force: false) },
                onRescan: {
                    reviewPayload = nil
                    startScanOrBlock()
                },
                onUploadAnyway: { beginUpload(payload, force: true) },
                onDelete: {
                    deleteScan(scanId: payload.scanId, projectId: payload.projectId)
                    reviewPayload = nil
                }
            )
        }
        // Item-based sheet avoids the blank content SwiftUI can show with `if let` inside isPresented.
        .sheet(item: $uploadSheet) { token in
            NavigationStack {
                UploadStatusView(queue: environment.uploadQueue, scanId: token.id) {
                    uploadSheet = nil
                    reviewPayload = nil
                }
            }
            .presentationDetents([.medium, .large])
            .preferredColorScheme(.dark)
        }
        .alert("Upload failed", isPresented: Binding(
            get: { uploadErrorMessage != nil },
            set: { if !$0 { uploadErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { uploadErrorMessage = nil }
        } message: {
            Text(uploadErrorMessage ?? "Could not write the scan package.")
        }
        .sheet(isPresented: $showUnsupported) {
            NavigationStack {
                UnsupportedDeviceView(onViewProjects: { showUnsupported = false })
            }
        }
        .alert("Delete this scan?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    deleteScan(scanId: pendingDelete.id, projectId: pendingDelete.projectId)
                }
                pendingDelete = nil
            }
        } message: {
            Text("Removes the local package and list entry. This cannot be undone.")
        }
        .alert("Delete this project?", isPresented: $showDeleteProjectConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteEntireProject()
            }
        } message: {
            Text("Removes the project and all of its local scans. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func content(_ project: Project) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if let address = project.address, !address.isEmpty {
                        Text(address)
                            .foregroundStyle(LiDirtColors.textSecondary)
                    }
                    capabilityBadge
                    Button {
                        openContourMap(for: project)
                    } label: {
                        Label("Topo / contour map", systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LiDirtSecondaryButtonStyle())

                    Text("Overlays LiDAR contours on USGS topo. Type the contour interval on the map.")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)

                    Button {
                        startScanOrBlock()
                    } label: {
                        Label("Start scan", systemImage: "cube.transparent")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LiDirtPrimaryButtonStyle(disabled: !DeviceCapability.canStartScan))
                    .disabled(!DeviceCapability.canStartScan)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(LiDirtColors.gunmetalElevated)

            Section("Scans") {
                if project.scanSummaries.isEmpty {
                    Text("No scans yet.")
                        .foregroundStyle(LiDirtColors.textSecondary)
                        .listRowBackground(LiDirtColors.gunmetalElevated)
                }
                ForEach(project.scanSummaries) { scan in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scan.capturedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(LiDirtColors.textPrimary)
                        HStack {
                            if let score = scan.qualityScore {
                                Text("Score \(score)")
                            }
                            Text(scan.uploadStatus.rawValue)
                            Text("\(scan.passCount) passes")
                        }
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)
                    }
                    .listRowBackground(LiDirtColors.gunmetalElevated)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            pendingDelete = scan
                            showDeleteConfirm = true
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var capabilityBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(DeviceCapability.canStartScan ? LiDirtColors.coverageGood : LiDirtColors.coverageThin)
                .frame(width: 8, height: 8)
            Text(DeviceCapability.canStartScan ? "LiDAR capture available" : "LiDAR required — capture blocked")
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textSecondary)
        }
    }

    private func startScanOrBlock() {
        if DeviceCapability.canStartScan {
            showScan = true
        } else {
            showUnsupported = true
        }
    }

    private func openContourMap(for project: Project) {
        siteMapHeightmap = nil
        siteMapOrientation = .unavailable

        // Prefer in-memory review payload, then latest packaged scan with GPS.
        if let review = reviewPayload, let heightmap = review.heightmap {
            siteMapHeightmap = heightmap
            siteMapOrientation = review.orientation
        } else {
            let candidates = project.scanSummaries.sorted { $0.capturedAt > $1.capturedAt }
            for scan in candidates {
                let dir: URL
                if let path = scan.localPackagePath {
                    dir = URL(fileURLWithPath: path)
                } else {
                    dir = environment.localScanStore.packageURL(for: scan.id)
                }
                if let loaded = try? ScanPackageReader.load(from: dir) {
                    siteMapHeightmap = loaded.heightmap
                    siteMapOrientation = loaded.orientation
                    break
                }
            }
        }
        showSiteMap = true
    }

    private func deleteScan(scanId: UUID, projectId: UUID) {
        _ = environment.projectStore.deleteScanSummary(projectId: projectId, scanId: scanId)
        environment.localScanStore.deletePackage(scanId: scanId)
        environment.uploadQueue.remove(scanId)
    }

    private func deleteEntireProject() {
        guard let removed = environment.projectStore.deleteProject(id: projectId) else { return }
        for scan in removed.scanSummaries {
            environment.localScanStore.deletePackage(scanId: scan.id)
            environment.uploadQueue.remove(scan.id)
        }
        dismiss()
    }

    private func beginUpload(_ payload: ReviewPayload, force: Bool) {
        guard let heightmap = payload.heightmap else { return }
        _ = force

        let metadata = ScanPackageWriter.makeMetadata(
            scanId: payload.scanId,
            projectId: payload.projectId,
            heightmap: heightmap,
            metrics: payload.metrics,
            durationSec: payload.durationSec,
            minSamplesPerCell: DEMBuilder.defaultMinSamplesPerCell,
            preferredContourIntervalInches: environment.preferredContourIntervalInches,
            controlPointsCount: payload.controlPins.count,
            hasLiDAR: DeviceCapability.supportsLiDARSceneReconstruction,
            orientation: payload.orientation
        )

        let dir = environment.localScanStore.packageURL(for: payload.scanId)
        do {
            let package = try ScanPackageWriter.writePackage(
                to: dir,
                metadata: metadata,
                heightmap: heightmap
            )
            environment.uploadQueue.enqueue(
                scanId: payload.scanId,
                projectId: payload.projectId,
                packageDirectory: package.directory
            )

            let summary = ScanSummary(
                id: payload.scanId,
                projectId: payload.projectId,
                qualityScore: payload.metrics.qualityScore,
                coverageRatio: payload.metrics.coverageRatio,
                passCount: payload.metrics.passCount,
                uploadStatus: .queued,
                localPackagePath: package.directory.path
            )
            if environment.projectStore.project(id: payload.projectId)?.scanSummaries.contains(where: { $0.id == payload.scanId }) == true {
                environment.projectStore.updateScanSummary(summary)
            } else {
                environment.projectStore.addScanSummary(summary)
            }

            uploadSheet = UploadSheetToken(id: payload.scanId)
            let scanId = payload.scanId
            Task {
                await environment.uploadQueue.processAll()
                if let accepted = environment.uploadQueue.items.first(where: { $0.id == scanId }) {
                    var updated = summary
                    updated.uploadStatus = accepted.status
                    environment.projectStore.updateScanSummary(updated)
                }
            }
        } catch {
            uploadErrorMessage = error.localizedDescription
        }
    }
}

private struct UploadSheetToken: Identifiable {
    let id: UUID
}

struct ReviewPayload: Identifiable, Hashable {
    var id: UUID { scanId }
    var scanId: UUID
    var projectId: UUID
    var heightmap: HeightmapResult?
    var metrics: QualityMetrics
    var durationSec: TimeInterval
    var controlPins: [ControlPin]
    var orientation: ScanOrientationSnapshot

    static func == (lhs: ReviewPayload, rhs: ReviewPayload) -> Bool {
        lhs.scanId == rhs.scanId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(scanId)
    }
}
