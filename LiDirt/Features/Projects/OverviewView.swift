import SwiftUI

/// Field Overview home — everything reachable from here (no bottom tabs).
struct OverviewView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showSettings = false

    private var projects: [Project] {
        environment.projectStore.projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var totalScans: Int {
        projects.reduce(0) { $0 + $1.scanSummaries.count }
    }

    private var greetingName: String {
        if let email = environment.authService.currentUser?.email,
           let local = email.split(separator: "@").first, !local.isEmpty {
            return local.capitalized
        }
        return "there"
    }

    private var dateEyebrow: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                quickLinks
                startScanCTA
                metricGrid
                recentProjects
                deviceStrip
            }
            .padding(20)
        }
        .background(
            ZStack {
                LiDirtColors.gunmetal
                RadialGradient(
                    colors: [
                        LiDirtColors.constructionYellow.opacity(0.05),
                        .clear
                    ],
                    center: UnitPoint(x: 0.85, y: -0.05),
                    startRadius: 20,
                    endRadius: 320
                )
            }
            .ignoresSafeArea()
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 8) {
                    BrandMark(size: 28)
                    HStack(spacing: 0) {
                        Text("Li")
                            .foregroundStyle(LiDirtColors.textPrimary)
                        Text("Dirt")
                            .foregroundStyle(LiDirtColors.constructionYellow)
                    }
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("LiDirt")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(environment)
        }
        .task {
            await environment.syncFromCloud()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateEyebrow.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(LiDirtColors.textMuted)
            Text("Good \(dayPart), \(greetingName).")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(LiDirtColors.textPrimary)
            Text("Here’s what’s happening across your job sites.")
                .font(LiDirtTypography.body)
                .foregroundStyle(LiDirtColors.textMuted)
        }
    }

    private var dayPart: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        default: return "evening"
        }
    }

    private var quickLinks: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            NavigationLink(value: WorkspaceRoute.projects) {
                Label("Projects", systemImage: "folder.fill")
                    .font(LiDirtTypography.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(LiDirtSecondaryButtonStyle())

            NavigationLink(value: WorkspaceRoute.models) {
                Label("3D Models", systemImage: "cube.transparent")
                    .font(LiDirtTypography.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(LiDirtSecondaryButtonStyle())

            NavigationLink(value: WorkspaceRoute.priceBook) {
                Label("Price Book", systemImage: "dollarsign.circle")
                    .font(LiDirtTypography.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(LiDirtSecondaryButtonStyle())

            NavigationLink(value: WorkspaceRoute.liveMap) {
                Label("Live map", systemImage: "location.north.line")
                    .font(LiDirtTypography.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(LiDirtSecondaryButtonStyle())
        }
    }

    private var startScanCTA: some View {
        NavigationLink(value: WorkspaceRoute.projects) {
            Label("Start new scan", systemImage: "viewfinder")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(LiDirtPrimaryButtonStyle())
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            NavigationLink(value: WorkspaceRoute.projects) {
                metricCard(
                    title: "Active projects",
                    value: String(format: "%02d", projects.count),
                    note: projects.isEmpty ? "Create your first site" : "\(min(projects.count, 2)) updated recently",
                    icon: "folder.fill"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: WorkspaceRoute.projects) {
                metricCard(
                    title: "Scans on device",
                    value: String(format: "%02d", totalScans),
                    note: DeviceCapability.canStartScan ? "LiDAR ready" : "LiDAR required",
                    icon: "cube.transparent"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: WorkspaceRoute.models) {
                metricCard(
                    title: "3D models",
                    value: String(format: "%02d", packagedModelCount),
                    note: "Open proposed-grade editor",
                    icon: "square.3.layers.3d.down.right"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: WorkspaceRoute.priceBook) {
                metricCard(
                    title: "Price Book",
                    value: String(format: "%02d", RegionalPriceCatalog.default.materials.count),
                    note: "OH / PA / WV yard rates",
                    icon: "dollarsign.circle"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var packagedModelCount: Int {
        projects.reduce(0) { partial, project in
            partial + project.scanSummaries.filter { $0.localPackagePath != nil }.count
        }
    }

    private func metricCard(title: String, value: String, note: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LiDirtColors.constructionYellow)
                    .frame(width: 32, height: 32)
                    .background(LiDirtColors.gunmetalDeep, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
            }
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(LiDirtColors.textMuted)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(LiDirtColors.textPrimary)
            Text(note)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LiDirtColors.gunmetalElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LiDirtColors.hairline, lineWidth: 1)
                )
        )
    }

    private var recentProjects: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR WORKSPACE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(LiDirtColors.textMuted)
                    Text("Recent projects")
                        .font(LiDirtTypography.headline)
                        .foregroundStyle(LiDirtColors.textPrimary)
                }
                Spacer()
                NavigationLink(value: WorkspaceRoute.projects) {
                    Text("View all")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.constructionYellow)
                }
            }

            if projects.isEmpty {
                Text("No projects yet. Open Projects to create one, then start a scan.")
                    .font(LiDirtTypography.body)
                    .foregroundStyle(LiDirtColors.textMuted)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(panelBackground)
            } else {
                ForEach(projects.prefix(4)) { project in
                    NavigationLink(value: WorkspaceRoute.project(project.id)) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(LiDirtColors.gunmetalDeep)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "map")
                                    .foregroundStyle(LiDirtColors.constructionYellow)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.name)
                                    .font(LiDirtTypography.headline)
                                    .foregroundStyle(LiDirtColors.textPrimary)
                                Text(project.address?.isEmpty == false
                                     ? project.address!
                                     : "\(project.scanSummaries.count) scans · updated \(project.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(LiDirtTypography.caption)
                                    .foregroundStyle(LiDirtColors.textMuted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(LiDirtColors.textMuted)
                        }
                        .padding(12)
                        .background(panelBackground)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var deviceStrip: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(DeviceCapability.canStartScan ? LiDirtColors.coverageGood : LiDirtColors.coverageThin)
                .frame(width: 8, height: 8)
            Text(DeviceCapability.canStartScan
                 ? "LiDAR capture available on this device."
                 : "LiDAR Pro required for field capture.")
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textSecondary)
            Spacer()
        }
        .padding(12)
        .background(panelBackground)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LiDirtColors.gunmetalElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LiDirtColors.hairline, lineWidth: 1)
            )
    }
}
