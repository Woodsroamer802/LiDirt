import SwiftUI

/// App navigation routes from Overview (no bottom tab bar).
enum WorkspaceRoute: Hashable {
    case projects
    case models
    case priceBook
    case liveMap
    case project(UUID)
}

/// Single NavigationStack: Overview home → Projects / 3D Models / project detail.
struct MainTabView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            OverviewView()
                .navigationDestination(for: WorkspaceRoute.self) { route in
                    switch route {
                    case .projects:
                        ProjectListView()
                    case .models:
                        ModelsListView()
                    case .priceBook:
                        PriceBookView()
                    case .liveMap:
                        LiveMapView()
                    case .project(let id):
                        ProjectDetailView(projectId: id)
                    }
                }
        }
        .tint(LiDirtColors.constructionYellow)
    }
}
