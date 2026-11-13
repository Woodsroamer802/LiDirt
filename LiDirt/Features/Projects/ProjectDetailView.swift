import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let projectId: UUID

    @State private var showScan = false
    @State private var showUnsupported = false
    @State private var reviewPayload: ReviewPayload?
    @State private var uploadScanId: UUID?
    @State private var showUpload = false

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
            ScanSessionView(projectId: projectId) { scanId, heightmap, metrics, duration, pins, projectId in
                showScan = false
                reviewPayload = ReviewPayload(
                    scanId: scanId,
                    projectId: projectId,
                    heightmap: heightmap,
                    metrics: metrics,
                    durationSec: duration,
                    controlPins: pins
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
                onUpload: { beginUpload(payload, force: false) },
                onRescan: {
                    reviewPayload = nil
                    startScanOrBlock()
                },
                onUploadAnyway: { beginUpload(payload, force: true) }
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
            hasLiDAR: DeviceCapability.supportsLiDARSceneReconstruction
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
            let projectId = payload.projectId
            Task {
                await environment.uploadQueue.processAll()
                if let accepted = environment.uploadQueue.items.first(where: { $0.id == scanId }) {
                    var updated = summary
                    updated.uploadStatus = accepted.status
                    environment.projectStore.updateScanSummary(updated)
                    _ = projectId
                }
            }
        } catch {
            // Keep operator on review; surface via upload sheet failure after enqueue attempt.
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

    static func == (lhs: ReviewPayload, rhs: ReviewPayload) -> Bool {
        lhs.scanId == rhs.scanId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(scanId)
    }
}
