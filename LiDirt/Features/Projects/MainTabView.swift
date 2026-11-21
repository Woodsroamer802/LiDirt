import SwiftUI

/// Top-level workspace tabs matching the Figma Make sidebar (Overview · Projects · 3D Models).
enum WorkspaceTab: Hashable {
    case overview
    case projects
    case models
}

struct MainTabView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selectedTab: WorkspaceTab = .overview
    @State private var projectsPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                OverviewView(selectedTab: $selectedTab) { projectId in
                    projectsPath = NavigationPath()
                    projectsPath.append(projectId)
                    selectedTab = .projects
                }
            }
            .tabItem {
                Label("Overview", systemImage: "square.grid.2x2.fill")
            }
            .tag(WorkspaceTab.overview)

            NavigationStack(path: $projectsPath) {
                ProjectListView()
                    .navigationDestination(for: UUID.self) { id in
                        ProjectDetailView(projectId: id)
                    }
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
