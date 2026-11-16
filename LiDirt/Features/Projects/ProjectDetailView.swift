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
    @State private var showSiteMap = false
    @State private var siteMapHeightmap: HeightmapResult?
    @State private var siteMapOrientation: ScanOrientationSnapshot = .unavailable
    @State private var isSavingPackage = false
    @State private var packageHint: String?

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
        .sheet(isPresented: $showSiteMap) {
            NavigationStack {
                SiteMapView(
                    projectName: project?.name ?? "Site",
                    projectId: projectId,
                    heightmap: siteMapHeightmap,
                    orientation: siteMapOrientation,
                    contourIntervalInches: environment.preferredContourIntervalInches,
                    contourSurfaceMode: environment.contourSurfaceMode,
                    jobSite: project?.jobSite,
                    initialAddress: project?.address,
                    onIntervalChange: { environment.savePreferredContourIntervalInches($0) },
                    onSurfaceModeChange: { environment.saveContourSurfaceMode($0) },
                    onJobSiteChange: { bounds in
                        guard var updated = environment.projectStore.project(id: projectId) else { return }
                        updated.jobSite = bounds
                        environment.projectStore.update(updated)
                    }
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
                // Persist package in background so past scans can be reopened / uploaded later.
                if let heightmap {
                    persistPackageAfterFinish(
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
                preferredContourSurfaceMode: environment.contourSurfaceMode,
                projectName: project?.name ?? "Scan",
                orientation: payload.orientation,
                onContourIntervalChange: { environment.savePreferredContourIntervalInches($0) },
                onContourSurfaceModeChange: { environment.saveContourSurfaceMode($0) },
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
                        Label("Job Site map", systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LiDirtSecondaryButtonStyle())

                    Text("Finished map: tap Job Site map above (uses latest saved scan). After Finish, also use Open Job Site map on Scan review.")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)

                    if isSavingPackage, let packageHint {
                        Text(packageHint)
                            .font(LiDirtTypography.caption)
                            .foregroundStyle(LiDirtColors.constructionYellow)
                    }

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
                    Button {
                        openScan(scan)
                    } label: {
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
                            Text(scan.localPackagePath == nil
                                 ? "Tap to open (needs saved package)"
                                 : "Tap to review / upload · Open Job Site map from review")
                                .font(LiDirtTypography.caption)
                                .foregroundStyle(LiDirtColors.constructionYellow)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
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

    private func openScan(_ scan: ScanSummary) {
        // Prefer live review payload if it's the same scan (already on that screen).
        if let review = reviewPayload, review.scanId == scan.id {
            return
        }
        let dir: URL
        if let path = scan.localPackagePath {
            dir = URL(fileURLWithPath: path)
        } else {
            dir = environment.localScanStore.packageURL(for: scan.id)
        }
        guard let loaded = try? ScanPackageReader.load(from: dir) else {
            uploadErrorMessage = "No saved package for this scan yet. After Finish, wait for “Scan package saved”, then tap again — or use Upload on the review screen right after Finish."
            return
        }
        let q = loaded.metadata.quality
        let metrics = QualityMetrics(
            coverageRatio: q.coverageRatio,
            meanSampleCount: q.meanSampleCount,
            rmsResidualM: q.rmsResidualM,
            holeRatio: q.holeRatio,
            passCount: loaded.metadata.capture.passCount,
            qualityScore: q.qualityScore
        )
        reviewPayload = ReviewPayload(
            scanId: scan.id,
            projectId: scan.projectId,
            heightmap: loaded.heightmap,
            metrics: metrics,
            durationSec: loaded.metadata.capture.durationSec,
            controlPins: [],
            orientation: loaded.orientation
        )
    }

    /// Write local package after Finish so the scan list can reopen / upload later.
    private func persistPackageAfterFinish(
        scanId: UUID,
        projectId: UUID,
        heightmap: HeightmapResult,
        metrics: QualityMetrics,
        durationSec: TimeInterval,
        controlPins: [ControlPin],
        orientation: ScanOrientationSnapshot
    ) {
        isSavingPackage = true
        packageHint = "Saving scan package in background…"
        let interval = environment.preferredContourIntervalInches
        let dir = environment.localScanStore.packageURL(for: scanId)
        Task(priority: .utility) {
            do {
                let metadata = ScanPackageWriter.makeMetadata(
                    scanId: scanId,
                    projectId: projectId,
                    heightmap: heightmap,
                    metrics: metrics,
                    durationSec: durationSec,
                    minSamplesPerCell: DEMBuilder.defaultMinSamplesPerCell,
                    preferredContourIntervalInches: interval,
                    controlPointsCount: controlPins.count,
                    hasLiDAR: DeviceCapability.supportsLiDARSceneReconstruction,
                    orientation: orientation
                )
                let package = try await Task.detached(priority: .utility) {
                    try ScanPackageWriter.writePackage(
                        to: dir,
                        metadata: metadata,
                        heightmap: heightmap
                    )
                }.value
                var summary = ScanSummary(
                    id: scanId,
                    projectId: projectId,
                    qualityScore: metrics.qualityScore,
                    coverageRatio: metrics.coverageRatio,
                    passCount: metrics.passCount,
                    uploadStatus: .localOnly,
                    localPackagePath: package.directory.path
                )
                if let existing = environment.projectStore.project(id: projectId)?
                    .scanSummaries.first(where: { $0.id == scanId }) {
                    summary.uploadStatus = existing.uploadStatus
                    summary.capturedAt = existing.capturedAt
                }
                environment.projectStore.updateScanSummary(summary)
                isSavingPackage = false
                packageHint = "Scan package saved — tap the scan to review / upload anytime."
            } catch {
                isSavingPackage = false
                packageHint = nil
                uploadErrorMessage = "Could not save scan package: \(error.localizedDescription)"
            }
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
            hasLiDAR: DeviceCapability.supportsLiDARSceneReconstruction,
            orientation: payload.orientation
        )

        let dir = environment.localScanStore.packageURL(for: payload.scanId)
        isSavingPackage = true
        packageHint = "Preparing upload package…"
        Task {
            do {
                let package = try await Task.detached(priority: .userInitiated) {
                    try ScanPackageWriter.writePackage(
                        to: dir,
                        metadata: metadata,
                        heightmap: heightmap
                    )
                }.value
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

                isSavingPackage = false
                packageHint = nil
                uploadSheet = UploadSheetToken(id: payload.scanId)
                let scanId = payload.scanId
                await environment.uploadQueue.processAll()
                if let accepted = environment.uploadQueue.items.first(where: { $0.id == scanId }) {
                    var updated = summary
                    updated.uploadStatus = accepted.status
                    environment.projectStore.updateScanSummary(updated)
                }
            } catch {
                isSavingPackage = false
                packageHint = nil
                uploadErrorMessage = error.localizedDescription
            }
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
