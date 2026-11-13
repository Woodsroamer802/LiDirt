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
