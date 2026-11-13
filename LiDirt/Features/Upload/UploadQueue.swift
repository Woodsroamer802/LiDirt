import Foundation

struct QueuedUpload: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var projectId: UUID
    var packageDirectory: String
    var enqueuedAt: Date
    var lastError: String?
    var attemptCount: Int
    var status: ScanUploadStatus
}

@MainActor
final class UploadQueue: ObservableObject {
    @Published private(set) var items: [QueuedUpload] = []
    @Published private(set) var isProcessing = false

    private var uploadService: UploadService
    private let paths: FilePaths
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(paths: FilePaths, uploadService: UploadService, fileManager: FileManager = .default) {
        self.paths = paths
        self.uploadService = uploadService
        self.fileManager = fileManager
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func updateClient(_ client: APIClient) {
        uploadService = uploadService.withClient(client)
    }

    func enqueue(scanId: UUID, projectId: UUID, packageDirectory: URL) {
        let dest = paths.queuedPackageDirectory(scanId: scanId)
        try? fileManager.removeItem(at: dest)
        try? fileManager.copyItem(at: packageDirectory, to: dest)

        if let existing = items.firstIndex(where: { $0.id == scanId }) {
            items[existing].packageDirectory = dest.path
            items[existing].status = .queued
            items[existing].lastError = nil
        } else {
            items.append(
                QueuedUpload(
                    id: scanId,
                    projectId: projectId,
                    packageDirectory: dest.path,
                    enqueuedAt: Date(),
                    lastError: nil,
                    attemptCount: 0,
                    status: .queued
                )
            )
        }
        persist()
    }

    func processAll() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        for index in items.indices {
            guard items[index].status == .queued || items[index].status == .failed else { continue }
            await process(at: index)
        }
    }

    func retry(_ id: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .queued
        persist()
        await process(at: index)
    }

    func remove(_ id: UUID) {
        if let item = items.first(where: { $0.id == id }) {
            try? fileManager.removeItem(at: URL(fileURLWithPath: item.packageDirectory, isDirectory: true))
        }
        items.removeAll { $0.id == id }
        persist()
    }

    private func process(at index: Int) async {
        items[index].status = .uploading
        items[index].attemptCount += 1
        persist()

        let item = items[index]
        let dir = URL(fileURLWithPath: item.packageDirectory, isDirectory: true)
        let metadataURL = dir.appendingPathComponent("metadata.json")
        let heightmapURL = dir.appendingPathComponent("heightmap.f32")

        do {
            let metaData = try Data(contentsOf: metadataURL)
            let metadata = try ScanPackageWriter.decodeMetadata(from: metaData)
            let package = ScanPackage(
                directory: dir,
                metadata: metadata,
                heightmapURL: heightmapURL,
                metadataURL: metadataURL
            )
            _ = try await uploadService.upload(package: package, projectId: item.projectId)
            items[index].status = .accepted
            items[index].lastError = nil
        } catch {
            items[index].status = .failed
            items[index].lastError = error.localizedDescription
        }
        persist()
    }

    private var queueFileURL: URL {
        paths.uploadsQueueDirectory.appendingPathComponent("queue.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: queueFileURL),
              let decoded = try? decoder.decode([QueuedUpload].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    private func persist() {
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: queueFileURL, options: .atomic)
    }
}
