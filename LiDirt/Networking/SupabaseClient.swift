import Foundation

enum SupabaseError: LocalizedError {
    case notConfigured
    case notSignedIn
    case httpStatus(Int, String?)
    case decoding
    case auth(String)
    case emailConfirmationRequired

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Supabase is not configured."
        case .notSignedIn: return "Sign in to sync with Supabase."
        case .httpStatus(let code, let body):
            return "Supabase error (\(code)). \(body ?? "")"
        case .decoding: return "Could not read Supabase response."
        case .auth(let message): return message
        case .emailConfirmationRequired:
            return "Account created. Check your email to confirm, then sign in. (Or turn off Confirm email in Supabase Auth settings.)"
        }
    }
}

struct SupabaseSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: UUID
    var email: String
}

struct SupabaseRemoteProject: Codable, Sendable {
    var id: UUID
    var owner_id: UUID
    var name: String
    var address: String?
    var job_site: JobSiteBounds?
    var created_at: Date
    var updated_at: Date
    var scans: [SupabaseRemoteScan]?
}

struct SupabaseRemoteScan: Codable, Sendable {
    var id: UUID
    var project_id: UUID
    var owner_id: UUID
    var captured_at: Date
    var quality_score: Int?
    var coverage_ratio: Double?
    var pass_count: Int
    var upload_status: String
    var storage_path: String?
    var created_at: Date
}

/// Lightweight REST client for Auth + PostgREST + Storage (no SPM dependency).
actor SupabaseClient {
    static let shared = SupabaseClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var authSession: SupabaseSession?

    private init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: raw) { return date }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(raw)")
        }
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.authSession = Self.loadPersistedSession()
    }

    func currentSession() -> SupabaseSession? { authSession }

    func accessToken() -> String? { authSession?.accessToken }

    @discardableResult
    func signUp(email: String, password: String, displayName: String?) async throws -> SupabaseSession {
        struct Body: Encodable {
            var email: String
            var password: String
            var data: [String: String]?
        }
        var meta: [String: String]?
        if let displayName, !displayName.isEmpty {
            meta = ["display_name": displayName]
        }
        let data = try await postJSON(
            path: "/auth/v1/signup",
            body: Body(email: email, password: password, data: meta),
            authed: false
        )
        do {
            return try storeSession(from: data, fallbackEmail: email)
        } catch SupabaseError.emailConfirmationRequired {
            // Confirm-email projects return a user with no tokens. Try password sign-in
            // in case confirmation is already disabled / auto-confirmed.
            do {
                return try await signIn(email: email, password: password)
            } catch {
                throw SupabaseError.emailConfirmationRequired
            }
        }
    }

    @discardableResult
    func signIn(email: String, password: String) async throws -> SupabaseSession {
        struct Body: Encodable { var email: String; var password: String }
        let data = try await postJSON(
            path: "/auth/v1/token?grant_type=password",
            body: Body(email: email, password: password),
            authed: false
        )
        return try storeSession(from: data, fallbackEmail: email)
    }

    func signOut() async {
        if authSession != nil {
            _ = try? await request(path: "/auth/v1/logout", method: "POST", body: Data("{}".utf8), authed: true)
        }
        authSession = nil
        Self.clearPersistedSession()
    }

    func refreshIfNeeded() async throws {
        guard let current = authSession else { return }
        // Refresh a minute early.
        guard current.expiresAt.timeIntervalSinceNow < 60 else { return }
        struct Body: Encodable { var refresh_token: String }
        let data = try await postJSON(
            path: "/auth/v1/token?grant_type=refresh_token",
            body: Body(refresh_token: current.refreshToken),
            authed: false
        )
        _ = try storeSession(from: data, fallbackEmail: current.email)
    }

    func fetchProjects() async throws -> [SupabaseRemoteProject] {
        try await refreshIfNeeded()
        let data = try await request(
            path: "/rest/v1/projects?select=*,scans(*)&order=updated_at.desc",
            method: "GET",
            body: nil,
            authed: true,
            extraHeaders: ["Accept": "application/json"]
        )
        return try decoder.decode([SupabaseRemoteProject].self, from: data)
    }

    func upsertProject(_ project: Project, ownerId: UUID) async throws {
        try await refreshIfNeeded()
        struct Row: Encodable {
            var id: UUID
            var owner_id: UUID
            var name: String
            var address: String?
            var job_site: JobSiteBounds?
            var created_at: Date
            var updated_at: Date
        }
        let row = Row(
            id: project.id,
            owner_id: ownerId,
            name: project.name,
            address: project.address,
            job_site: project.jobSite,
            created_at: project.createdAt,
            updated_at: project.updatedAt
        )
        _ = try await request(
            path: "/rest/v1/projects",
            method: "POST",
            body: try encoder.encode(row),
            authed: true,
            extraHeaders: [
                "Content-Type": "application/json",
                "Prefer": "resolution=merge-duplicates,return=minimal"
            ]
        )
    }

    func deleteProject(id: UUID) async throws {
        try await refreshIfNeeded()
        _ = try await request(
            path: "/rest/v1/projects?id=eq.\(id.uuidString)",
            method: "DELETE",
            body: nil,
            authed: true
        )
    }

    func uploadScanPackage(
        scanId: UUID,
        projectId: UUID,
        ownerId: UUID,
        package: ScanPackage,
        qualityScore: Int?,
        coverageRatio: Double?,
        passCount: Int
    ) async throws -> UploadAccepted {
        try await refreshIfNeeded()
        let basePath = "\(ownerId.uuidString)/\(projectId.uuidString)/\(scanId.uuidString)"
        let metadataPath = "\(basePath)/metadata.json"
        let heightmapPath = "\(basePath)/heightmap.f32"

        let metadataData = try Data(contentsOf: package.metadataURL)
        let heightmapData = try Data(contentsOf: package.heightmapURL)

        try await uploadObject(path: metadataPath, data: metadataData, contentType: "application/json")
        try await uploadObject(path: heightmapPath, data: heightmapData, contentType: "application/octet-stream")

        struct Row: Encodable {
            var id: UUID
            var project_id: UUID
            var owner_id: UUID
            var captured_at: Date
            var quality_score: Int?
            var coverage_ratio: Double?
            var pass_count: Int
            var upload_status: String
            var storage_path: String
            var metadata: [String: String]
        }
        let capturedAt = ISO8601DateFormatter().date(from: package.metadata.capturedAt) ?? Date()
        let row = Row(
            id: scanId,
            project_id: projectId,
            owner_id: ownerId,
            captured_at: capturedAt,
            quality_score: qualityScore ?? package.metadata.quality.qualityScore,
            coverage_ratio: coverageRatio ?? package.metadata.quality.coverageRatio,
            pass_count: passCount > 0 ? passCount : package.metadata.capture.passCount,
            upload_status: "accepted",
            storage_path: basePath,
            metadata: ["format": "lidirt-scan-v1"]
        )
        _ = try await request(
            path: "/rest/v1/scans",
            method: "POST",
            body: try encoder.encode(row),
            authed: true,
            extraHeaders: [
                "Content-Type": "application/json",
                "Prefer": "resolution=merge-duplicates,return=minimal"
            ]
        )
        return UploadAccepted(scanId: scanId.uuidString, status: "accepted", stub: false)
    }

    // MARK: - Private

    private func uploadObject(path: String, data: Data, contentType: String) async throws {
        let encodedPath = path.split(separator: "/").map {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        _ = try await request(
            path: "/storage/v1/object/\(SupabaseConfig.scanPackagesBucket)/\(encodedPath)",
            method: "POST",
            body: data,
            authed: true,
            extraHeaders: [
                "Content-Type": contentType,
                "x-upsert": "true"
            ]
        )
    }

    private func postJSON<T: Encodable>(path: String, body: T, authed: Bool) async throws -> Data {
        try await request(
            path: path,
            method: "POST",
            body: try encoder.encode(body),
            authed: authed,
            extraHeaders: ["Content-Type": "application/json"]
        )
    }

    private func request(
        path: String,
        method: String,
        body: Data?,
        authed: Bool,
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        // Build from absolute string so query params on auth token routes survive.
        guard let fullURL = URL(string: SupabaseConfig.projectURL.absoluteString + path) else {
            throw SupabaseError.notConfigured
        }

        var request = URLRequest(url: fullURL)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if authed {
            guard let token = authSession?.accessToken else { throw SupabaseError.notSignedIn }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8)
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = obj["msg"] as? String ?? obj["error_description"] as? String ?? obj["message"] as? String {
                throw SupabaseError.auth(message)
            }
            throw SupabaseError.httpStatus(http.statusCode, bodyText)
        }
        return data
    }

    private func storeSession(from data: Data, fallbackEmail: String) throws -> SupabaseSession {
        // Parse with JSONSerialization so missing/optional tokens (email-confirm signup)
        // don't surface as opaque DecodingError ("The data couldn't be read because it is missing").
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SupabaseError.decoding
        }

        let accessToken = root["access_token"] as? String
        let refreshToken = root["refresh_token"] as? String
        let userObj = root["user"] as? [String: Any]
        let userIdString = (userObj?["id"] as? String) ?? (root["id"] as? String)
        let email = (userObj?["email"] as? String) ?? (root["email"] as? String) ?? fallbackEmail

        guard let accessToken, !accessToken.isEmpty,
              let refreshToken, !refreshToken.isEmpty,
              let userIdString,
              let userId = UUID(uuidString: userIdString) else {
            // Signup with "Confirm email" returns 200 + user, but no session tokens.
            if userIdString != nil || userObj != nil {
                throw SupabaseError.emailConfirmationRequired
            }
            if let message = root["msg"] as? String
                ?? root["error_description"] as? String
                ?? root["message"] as? String {
                throw SupabaseError.auth(message)
            }
            throw SupabaseError.decoding
        }

        let expiresAt: Date
        if let expiresAtUnix = root["expires_at"] as? Double {
            expiresAt = Date(timeIntervalSince1970: expiresAtUnix)
        } else if let expiresAtUnix = root["expires_at"] as? Int {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(expiresAtUnix))
        } else if let expiresIn = root["expires_in"] as? Int {
            expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        } else if let expiresIn = root["expires_in"] as? Double {
            expiresAt = Date().addingTimeInterval(expiresIn)
        } else {
            expiresAt = Date().addingTimeInterval(3600)
        }

        let session = SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userId: userId,
            email: email
        )
        authSession = session
        Self.persist(session)
        return session
    }

    private static let sessionDefaultsKey = "lidirt.supabase.session"

    private static func persist(_ session: SupabaseSession) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else { return }
        UserDefaults.standard.set(data, forKey: sessionDefaultsKey)
    }

    private static func loadPersistedSession() -> SupabaseSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionDefaultsKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SupabaseSession.self, from: data)
    }

    private static func clearPersistedSession() {
        UserDefaults.standard.removeObject(forKey: sessionDefaultsKey)
    }
}
