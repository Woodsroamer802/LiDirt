import Foundation

struct UploadAccepted: Codable, Sendable {
    var scanId: String
    var status: String
    var stub: Bool?
}

final class UploadService: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func withClient(_ client: APIClient) -> UploadService {
        UploadService(client: client)
    }

    func upload(package: ScanPackage, projectId: UUID) async throws -> UploadAccepted {
        // Prefer Supabase when signed in.
        if let session = await SupabaseClient.shared.currentSession() {
            let scanId = UUID(uuidString: package.metadata.scanId) ?? UUID()
            return try await SupabaseClient.shared.uploadScanPackage(
                scanId: scanId,
                projectId: projectId,
                ownerId: session.userId,
                package: package,
                qualityScore: package.metadata.quality.qualityScore,
                coverageRatio: package.metadata.quality.coverageRatio,
                passCount: package.metadata.capture.passCount
            )
        }

        // Legacy multipart fallback (stub or custom API host).
        let metadataData = try Data(contentsOf: package.metadataURL)
        let heightmapData = try Data(contentsOf: package.heightmapURL)

        let url = Endpoints.scans(base: client.baseURL, projectId: projectId)
        let responseData = try await client.postMultipart(
            url: url,
            fields: ["metadata": metadataData],
            fileParts: [
                (
                    name: "heightmap",
                    filename: "heightmap.f32",
                    mime: "application/octet-stream",
                    data: heightmapData
                )
            ]
        )
        return try JSONDecoder().decode(UploadAccepted.self, from: responseData)
    }
}
