import Foundation

struct LocalScanRecord: Codable, Identifiable, Sendable {
    var id: UUID
    var projectId: UUID
    var packageDirectory: String
    var createdAt: Date
}

final class LocalScanStore: Sendable {
    private let paths: FilePaths

    init(paths: FilePaths) {
        self.paths = paths
    }

    func packageURL(for scanId: UUID) -> URL {
        paths.scanPackageDirectory(scanId: scanId)
    }

    func deletePackage(scanId: UUID) {
        // FileManager is not Sendable; use the shared default at the call site.
        try? FileManager.default.removeItem(at: packageURL(for: scanId))
    }
}
