import SwiftUI

/// Top-level workspace tabs matching the Figma Make sidebar (Projects · 3D Models).
enum WorkspaceTab: Hashable {
    case projects
    case models
}

struct MainTabView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selectedTab: WorkspaceTab = .projects

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ProjectListView()
            }
            .tabItem {
                Label("Projects", systemImage: "folder.fill")
            }
            .tag(WorkspaceTab.projects)

            NavigationStack {
                ModelsListView()
            }
            .tabItem {
                Label("3D Models", systemImage: "cube.transparent")
            }
            .tag(WorkspaceTab.models)
        }
        .tint(LiDirtColors.constructionYellow)
        .toolbarBackground(LiDirtColors.gunmetalElevated, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
