import Foundation

struct Project: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var address: String?
    var createdAt: Date
    var updatedAt: Date
    var scanSummaries: [ScanSummary]

    init(
        id: UUID = UUID(),
        name: String,
        address: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        scanSummaries: [ScanSummary] = []
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.scanSummaries = scanSummaries
    }
}

struct ScanSummary: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var projectId: UUID
    var capturedAt: Date
    var qualityScore: Int?
    var coverageRatio: Double?
    var passCount: Int
    var uploadStatus: ScanUploadStatus
    var localPackagePath: String?

    init(
        id: UUID = UUID(),
        projectId: UUID,
        capturedAt: Date = Date(),
        qualityScore: Int? = nil,
        coverageRatio: Double? = nil,
        passCount: Int = 0,
        uploadStatus: ScanUploadStatus = .localOnly,
        localPackagePath: String? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.capturedAt = capturedAt
        self.qualityScore = qualityScore
        self.coverageRatio = coverageRatio
        self.passCount = passCount
        self.uploadStatus = uploadStatus
        self.localPackagePath = localPackagePath
    }
}

enum ScanUploadStatus: String, Codable, Sendable {
    case localOnly
    case queued
    case uploading
    case accepted
    case failed
}

struct ControlPin: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var label: String
    var x: Double
    var y: Double
    var z: Double

    init(id: UUID = UUID(), label: String, x: Double, y: Double, z: Double) {
        self.id = id
        self.label = label
        self.x = x
        self.y = y
        self.z = z
    }
}
