import SwiftUI

@main
struct LiDirtApp: App {
    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
                .preferredColorScheme(.dark)
        }
    }
}

/// Shows a branded first frame immediately, then builds `AppEnvironment` off the
/// critical launch path so Xcode is less likely to sit on a blank gunmetal launch screen.
private struct AppBootstrapView: View {
    @StateObject private var bootstrap = AppBootstrap()

    var body: some View {
        Group {
            if let environment = bootstrap.environment {
                RootView()
                    .environmentObject(environment)
            } else {
                ZStack {
                    LiDirtColors.gunmetal.ignoresSafeArea()
                    VStack(spacing: 16) {
                        Text("LiDirt")
                            .font(LiDirtTypography.brand)
                            .foregroundStyle(LiDirtColors.constructionYellow)
                        ProgressView()
                            .tint(LiDirtColors.constructionYellow)
                        Text(bootstrap.status)
                            .font(LiDirtTypography.caption)
                            .foregroundStyle(LiDirtColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
            }
        }
        .tint(LiDirtColors.constructionYellow)
        .task {
            bootstrap.startIfNeeded()
        }
    }
}

@MainActor
private final class AppBootstrap: ObservableObject {
    @Published private(set) var environment: AppEnvironment?
    @Published private(set) var status = "Starting…"
    private var started = false

    func startIfNeeded() {
        guard !started else { return }
        started = true
        status = "Loading local projects…"
        // Yield so the first branded frame can paint before file I/O.
        Task { @MainActor in
            await Task.yield()
            environment = AppEnvironment()
        }
    }
}
