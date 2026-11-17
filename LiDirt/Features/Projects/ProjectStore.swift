import Foundation

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []

    private let paths: FilePaths
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(paths: FilePaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: projectsFileURL),
              let decoded = try? decoder.decode([Project].self, from: data) else {
            projects = []
            return
        }
        projects = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func createProject(name: String, address: String? = nil) -> Project {
        let project = Project(name: name, address: address)
        projects.insert(project, at: 0)
        persist()
        return project
    }

    func update(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        var updated = project
        updated.updatedAt = Date()
        projects[index] = updated
        projects.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func project(id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    func addScanSummary(_ summary: ScanSummary) {
        guard let index = projects.firstIndex(where: { $0.id == summary.projectId }) else { return }
        projects[index].scanSummaries.insert(summary, at: 0)
        projects[index].updatedAt = Date()
        persist()
    }

    func updateScanSummary(_ summary: ScanSummary) {
        guard let pIndex = projects.firstIndex(where: { $0.id == summary.projectId }),
              let sIndex = projects[pIndex].scanSummaries.firstIndex(where: { $0.id == summary.id }) else {
            return
        }
        projects[pIndex].scanSummaries[sIndex] = summary
        projects[pIndex].updatedAt = Date()
        persist()
    }

    @discardableResult
    func deleteScanSummary(projectId: UUID, scanId: UUID) -> ScanSummary? {
        guard let pIndex = projects.firstIndex(where: { $0.id == projectId }),
              let sIndex = projects[pIndex].scanSummaries.firstIndex(where: { $0.id == scanId }) else {
            return nil
        }
        let removed = projects[pIndex].scanSummaries.remove(at: sIndex)
        projects[pIndex].updatedAt = Date()
        persist()
        return removed
    }

    /// Removes the project and returns it so callers can delete local scan packages.
    @discardableResult
    func deleteProject(id: UUID) -> Project? {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = projects.remove(at: index)
        persist()
        return removed
    }

    /// Merge remote Supabase projects/scans into local cache without wiping local package paths.
    func replaceFromRemote(_ remote: [SupabaseRemoteProject]) {
        var byId = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        for row in remote {
            var local = byId[row.id] ?? Project(
                id: row.id,
                name: row.name,
                address: row.address,
                createdAt: row.created_at,
                updatedAt: row.updated_at,
                scanSummaries: [],
                jobSite: row.job_site
            )
            local.name = row.name
            local.address = row.address
            local.createdAt = row.created_at
            local.updatedAt = row.updated_at
            local.jobSite = row.job_site

            let remoteScans = row.scans ?? []
            var scanById = Dictionary(uniqueKeysWithValues: local.scanSummaries.map { ($0.id, $0) })
            for scan in remoteScans {
                var summary = scanById[scan.id] ?? ScanSummary(
                    id: scan.id,
                    projectId: scan.project_id,
                    capturedAt: scan.captured_at,
                    qualityScore: scan.quality_score,
                    coverageRatio: scan.coverage_ratio,
                    passCount: scan.pass_count,
                    uploadStatus: ScanUploadStatus(rawValue: scan.upload_status) ?? .accepted,
                    localPackagePath: nil
                )
                summary.capturedAt = scan.captured_at
                summary.qualityScore = scan.quality_score
                summary.coverageRatio = scan.coverage_ratio
                summary.passCount = scan.pass_count
                if summary.uploadStatus == .localOnly || summary.uploadStatus == .failed {
                    summary.uploadStatus = ScanUploadStatus(rawValue: scan.upload_status) ?? .accepted
                } else if scan.upload_status == "accepted" {
                    summary.uploadStatus = .accepted
                }
                // Keep existing localPackagePath when present.
                scanById[scan.id] = summary
            }
            local.scanSummaries = Array(scanById.values).sorted { $0.capturedAt > $1.capturedAt }
            byId[row.id] = local
        }
        projects = Array(byId.values).sorted { $0.updatedAt > $1.updatedAt }
        persist()
    }

    private var projectsFileURL: URL {
        paths.projectsDirectory.appendingPathComponent("projects.json")
    }

    private func persist() {
        guard let data = try? encoder.encode(projects) else { return }
        try? data.write(to: projectsFileURL, options: .atomic)
    }
}
