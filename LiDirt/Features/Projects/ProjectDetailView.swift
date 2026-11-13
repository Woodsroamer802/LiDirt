import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let projectId: UUID

    @State private var showScan = false
    @State private var showUnsupported = false
    @State private var reviewPayload: ReviewPayload?
    @State private var uploadScanId: UUID?
    @State private var showUpload = false
    @State private var pendingDelete: ScanSummary?
    @State private var showDeleteConfirm = false

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
        .sheet(isPresented: $showUpload) {
            if let uploadScanId {
                UploadStatusView(queue: environment.uploadQueue, scanId: uploadScanId) {
                    showUpload = false
                    reviewPayload = nil
                }
                .presentationDetents([.medium, .large])
            }
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

    private func deleteScan(scanId: UUID, projectId: UUID) {
        _ = environment.projectStore.deleteScanSummary(projectId: projectId, scanId: scanId)
        environment.localScanStore.deletePackage(scanId: scanId)
        environment.uploadQueue.remove(scanId)
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

            uploadScanId = payload.scanId
            showUpload = true
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
            uploadScanId = payload.scanId
            showUpload = true
        }
    }
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
