import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String?)
    case stubOffline
    case encoding

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .httpStatus(let code, let body):
            return "Upload failed (\(code)). \(body ?? "")"
        case .stubOffline:
            return "API unreachable — package kept in offline queue."
        case .encoding:
            return "Could not encode upload package."
        }
    }
}

final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    init(_ value: String? = nil) {
        self.value = value
    }

    func get() -> String? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set(_ newValue: String?) {
        lock.lock(); defer { lock.unlock() }
        value = newValue
    }
}

struct APIClient: Sendable {
    var baseURL: URL
    var tokenBox: TokenBox
    var session: URLSession
    /// When true, network calls simulate acceptance without hitting a real host.
    var useLocalStub: Bool

    init(
        baseURL: URL,
        tokenBox: TokenBox = TokenBox(),
        session: URLSession = .shared,
        useLocalStub: Bool? = nil
    ) {
        self.baseURL = baseURL
        self.tokenBox = tokenBox
        self.session = session
        // Stub when pointing at the example host so field builds work without a backend.
        if let useLocalStub {
            self.useLocalStub = useLocalStub
        } else {
            self.useLocalStub = baseURL.host?.contains("lidirt.example") == true
        }
    }

    func authorizedRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token = tokenBox.get() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func postMultipart(
        url: URL,
        fields: [String: Data],
        fileParts: [(name: String, filename: String, mime: String, data: Data)]
    ) async throws -> Data {
        if useLocalStub {
            // Stub API: accept package locally so field builds work without backend.
            let response: [String: Any] = [
                "scanId": UUID().uuidString,
                "status": "accepted",
                "stub": true
            ]
            return try JSONSerialization.data(withJSONObject: response)
        }

        let boundary = "LiDirt-\(UUID().uuidString)"
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        for (name, data) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }
        for part in fileParts {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(part.filename)\"\r\n"
                    .data(using: .utf8)!
            )
            body.append("Content-Type: \(part.mime)\r\n\r\n".data(using: .utf8)!)
            body.append(part.data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }
        return data
    }
}
