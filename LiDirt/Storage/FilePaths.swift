import Foundation

struct FilePaths: Sendable {
    static let shared = FilePaths()

    let applicationSupport: URL
    let projectsDirectory: URL
    let scansDirectory: URL
    let uploadsQueueDirectory: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LiDirt", isDirectory: true)
        applicationSupport = base
        projectsDirectory = base.appendingPathComponent("Projects", isDirectory: true)
        scansDirectory = base.appendingPathComponent("Scans", isDirectory: true)
        uploadsQueueDirectory = base.appendingPathComponent("UploadsQueue", isDirectory: true)

        for url in [applicationSupport, projectsDirectory, scansDirectory, uploadsQueueDirectory] {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    func scanPackageDirectory(scanId: UUID) -> URL {
        scansDirectory.appendingPathComponent("scan-\(scanId.uuidString)", isDirectory: true)
    }

    func queuedPackageDirectory(scanId: UUID) -> URL {
        uploadsQueueDirectory.appendingPathComponent("scan-\(scanId.uuidString)", isDirectory: true)
    }
}
