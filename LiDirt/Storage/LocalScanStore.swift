import Foundation

struct LocalScanRecord: Codable, Identifiable, Sendable {
    var id: UUID
    var projectId: UUID
    var packageDirectory: String
    var createdAt: Date
}

final class LocalScanStore: Sendable {
    private let paths: FilePaths
    private let fileManager: FileManager

    init(paths: FilePaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func packageURL(for scanId: UUID) -> URL {
        paths.scanPackageDirectory(scanId: scanId)
    }

    func deletePackage(scanId: UUID) {
        let url = packageURL(for: scanId)
        try? fileManager.removeItem(at: url)
    }
}
