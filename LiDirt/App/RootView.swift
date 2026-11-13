import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showLogin = false

    var body: some View {
        Group {
            if environment.authToken == nil {
                LoginView(onContinue: {
                    // Stub auth: accept any email and mint a local token.
                    environment.applyAuthToken("stub-\(UUID().uuidString)")
                })
            } else {
                NavigationStack {
                    ProjectListView()
                }
            }
        }
        .tint(LiDirtColors.constructionYellow)
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
    }
}

#Preview {
    RootView()
        .environmentObject(AppEnvironment())
}
