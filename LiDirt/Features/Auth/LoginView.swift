import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    var onAuthenticated: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var infoMessage: String?

    private enum Mode {
        case signIn
        case signUp
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [LiDirtColors.gunmetalDeep, LiDirtColors.gunmetal, LiDirtColors.gunmetalElevated],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 48)

                    VStack(spacing: 12) {
                        BrandMark(size: 128)
                        Text("LiDirt")
                            .font(LiDirtTypography.brand)
                            .foregroundStyle(LiDirtColors.constructionYellow)
                        Text("Field grade and volume estimating")
                            .font(LiDirtTypography.body)
                            .foregroundStyle(LiDirtColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Email")
                            .font(LiDirtTypography.caption)
                            .foregroundStyle(LiDirtColors.textMuted)
                        TextField("you@company.com", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(LiDirtColors.gunmetalElevated, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(LiDirtColors.textPrimary)

                        Text("Password")
                            .font(LiDirtTypography.caption)
                            .foregroundStyle(LiDirtColors.textMuted)
                        SecureField("••••••••", text: $password)
                            .textContentType(mode == .signUp ? .newPassword : .password)
                            .padding(14)
                            .background(LiDirtColors.gunmetalElevated, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(LiDirtColors.textPrimary)
                    }
                    .padding(.horizontal, 24)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(LiDirtTypography.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    if let infoMessage {
                        Text(infoMessage)
                            .font(LiDirtTypography.caption)
                            .foregroundStyle(LiDirtColors.constructionYellow)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }

                    Button(mode == .signIn ? "Sign in" : "Create account") {
                        Task { await submit() }
                    }
                    .buttonStyle(LiDirtPrimaryButtonStyle(disabled: !canSubmit || isWorking))
                    .disabled(!canSubmit || isWorking)
                    .padding(.horizontal, 24)

                    if isWorking {
                        ProgressView()
                            .tint(LiDirtColors.constructionYellow)
                    }

                    Button(mode == .signIn ? "Need an account? Sign up" : "Have an account? Sign in") {
                        mode = mode == .signIn ? .signUp : .signIn
                        errorMessage = nil
                        infoMessage = nil
                    }
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textSecondary)

                    Text("Accounts sync projects and scan packages through Supabase.")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer(minLength: 48)
                }
            }
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= 6
    }

    private func submit() async {
        errorMessage = nil
        infoMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let session: SupabaseSession
            if mode == .signIn {
                session = try await environment.authService.signIn(email: email, password: password)
            } else {
                session = try await environment.authService.signUp(email: email, password: password)
            }
            environment.applyAuthToken(session.accessToken)
            await environment.syncFromCloud()
            onAuthenticated()
        } catch {
            let text = error.localizedDescription
            if text.localizedCaseInsensitiveContains("confirm")
                || text.localizedCaseInsensitiveContains("check your email") {
                infoMessage = "Account created — confirm via email, then Sign in."
                mode = .signIn
            }
            errorMessage = text
        }
    }
}

#Preview {
    LoginView(onAuthenticated: {})
        .environmentObject(AppEnvironment())
}
