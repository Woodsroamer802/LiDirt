import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isRestoring = true

    var body: some View {
        Group {
            if isRestoring {
                ZStack {
                    LiDirtColors.gunmetal.ignoresSafeArea()
                    ProgressView("Checking session…")
                        .tint(LiDirtColors.constructionYellow)
                        .foregroundStyle(LiDirtColors.textSecondary)
                }
            } else if environment.authToken == nil {
                LoginView(onAuthenticated: {})
            } else {
                NavigationStack {
                    ProjectListView()
                }
            }
        }
        .tint(LiDirtColors.constructionYellow)
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .task {
            await restoreIfNeeded()
        }
    }

    private func restoreIfNeeded() async {
        defer { isRestoring = false }
        if let session = await environment.authService.restoreSession() {
            environment.applyAuthToken(session.accessToken)
            await environment.syncFromCloud()
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppEnvironment())
}
