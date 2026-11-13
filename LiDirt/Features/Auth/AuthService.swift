import Foundation

struct AuthUser: Codable, Equatable, Sendable {
    var email: String
    var displayName: String
}

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var currentUser: AuthUser?

    /// Stub login: no network. Enough for first shippable shell.
    func loginStub(email: String) -> AuthUser {
        let user = AuthUser(
            email: email.lowercased(),
            displayName: email.split(separator: "@").first.map(String.init) ?? "Operator"
        )
        currentUser = user
        return user
    }

    func logout() {
        currentUser = nil
    }
}
