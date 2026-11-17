import Foundation

struct AuthUser: Codable, Equatable, Sendable {
    var id: UUID?
    var email: String
    var displayName: String
}

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var currentUser: AuthUser?
    @Published private(set) var isBusy = false
    @Published var lastError: String?

    /// Restore a persisted Supabase session into the app environment token box.
    func restoreSession() async -> SupabaseSession? {
        let session = await SupabaseClient.shared.currentSession()
        guard let session else {
            currentUser = nil
            return nil
        }
        do {
            try await SupabaseClient.shared.refreshIfNeeded()
        } catch {
            // Stale refresh — clear and force re-login.
            await SupabaseClient.shared.signOut()
            currentUser = nil
            return nil
        }
        let refreshed = await SupabaseClient.shared.currentSession() ?? session
        currentUser = AuthUser(
            id: refreshed.userId,
            email: refreshed.email,
            displayName: refreshed.email.split(separator: "@").first.map(String.init) ?? "Operator"
        )
        return refreshed
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let session = try await SupabaseClient.shared.signIn(email: trimmed, password: password)
        currentUser = AuthUser(
            id: session.userId,
            email: session.email,
            displayName: session.email.split(separator: "@").first.map(String.init) ?? "Operator"
        )
        return session
    }

    func signUp(email: String, password: String) async throws -> SupabaseSession {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let display = trimmed.split(separator: "@").first.map(String.init)
        let session = try await SupabaseClient.shared.signUp(
            email: trimmed,
            password: password,
            displayName: display
        )
        currentUser = AuthUser(
            id: session.userId,
            email: session.email,
            displayName: display ?? "Operator"
        )
        return session
    }

    func logout() async {
        await SupabaseClient.shared.signOut()
        currentUser = nil
    }
}
