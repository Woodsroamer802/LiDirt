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

    private var projectsFileURL: URL {
        paths.projectsDirectory.appendingPathComponent("projects.json")
    }

    private func persist() {
        guard let data = try? encoder.encode(projects) else { return }
        try? data.write(to: projectsFileURL, options: .atomic)
    }
}
