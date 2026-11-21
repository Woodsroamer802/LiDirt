import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showNewProject = false
    @State private var newName = ""
    @State private var newAddress = ""
    @State private var showSettings = false
    @State private var pendingDeleteProject: Project?
    @State private var showDeleteProjectConfirm = false

    private var projects: [Project] {
        environment.projectStore.projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeading
                deviceBanner
                if projects.isEmpty {
                    emptyProjects
                } else {
                    ForEach(projects) { project in
                        NavigationLink(value: WorkspaceRoute.project(project.id)) {
                            projectCard(project)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                pendingDeleteProject = project
                                showDeleteProjectConfirm = true
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewProject = true
                } label: {
                    Label("New project", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewProject) {
            newProjectSheet
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(environment)
        }
        .alert("Delete this project?", isPresented: $showDeleteProjectConfirm) {
            Button("Cancel", role: .cancel) { pendingDeleteProject = nil }
            Button("Delete", role: .destructive) {
                if let pendingDeleteProject {
                    deleteProject(pendingDeleteProject)
                }
                pendingDeleteProject = nil
            }
        } message: {
            Text("Removes the project and all of its local scans. This cannot be undone.")
        }
        .task {
            await environment.syncFromCloud()
            await environment.uploadQueue.processAll()
        }
    }

    private var pageHeading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WORKSPACE")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(LiDirtColors.textMuted)
            Text("Manage every site from first scan through final invoice.")
                .font(LiDirtTypography.body)
                .foregroundStyle(LiDirtColors.textMuted)
        }
    }

    private func projectCard(_ project: Project) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LiDirtColors.gunmetalDeep)
                    .frame(width: 52, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(LiDirtColors.constructionYellow.opacity(0.35), lineWidth: 1)
                    )
                Image(systemName: "map")
                    .foregroundStyle(LiDirtColors.constructionYellow)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(LiDirtTypography.headline)
                    .foregroundStyle(LiDirtColors.textPrimary)
                if let address = project.address, !address.isEmpty {
                    Text(address)
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)
                        .lineLimit(1)
                }
                Text("\(project.scanSummaries.count) scans · updated \(project.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiDirtColors.textMuted)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LiDirtColors.gunmetalElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LiDirtColors.hairline, lineWidth: 1)
                )
        )
    }

    private var emptyProjects: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 36))
                .foregroundStyle(LiDirtColors.constructionYellow)
            Text("Projects workspace")
                .font(LiDirtTypography.headline)
                .foregroundStyle(LiDirtColors.textPrimary)
            Text("Create a project to start a field scan and build Contour maps + 3D models.")
                .font(LiDirtTypography.body)
                .foregroundStyle(LiDirtColors.textMuted)
                .multilineTextAlignment(.center)
            Button {
                showNewProject = true
            } label: {
                Label("New project", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LiDirtPrimaryButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LiDirtColors.gunmetalElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LiDirtColors.hairline, lineWidth: 1)
                )
        )
    }

    private func deleteProject(_ project: Project) {
        guard let removed = environment.projectStore.deleteProject(id: project.id) else { return }
        for scan in removed.scanSummaries {
            environment.localScanStore.deletePackage(scanId: scan.id)
            environment.uploadQueue.remove(scan.id)
        }
        Task {
            try? await SupabaseClient.shared.deleteProject(id: removed.id)
        }
    }

    private var deviceBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: DeviceCapability.canStartScan ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(
                    DeviceCapability.canStartScan
                    ? LiDirtColors.coverageGood
                    : LiDirtColors.constructionYellow
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(DeviceCapability.canStartScan ? "LiDAR ready" : "LiDAR required")
                    .font(LiDirtTypography.headline)
                    .foregroundStyle(LiDirtColors.textPrimary)
                Text(
                    DeviceCapability.canStartScan
                    ? "This device can capture field grade scans."
                    : "Capture needs a LiDAR Pro iPhone or iPad."
                )
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LiDirtColors.gunmetalElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LiDirtColors.hairline, lineWidth: 1)
                )
        )
    }

    private var newProjectSheet: some View {
        NavigationStack {
            Form {
                TextField("Project name", text: $newName)
                TextField("Address (optional)", text: $newAddress)
            }
            .scrollContentBackground(.hidden)
            .background(LiDirtColors.gunmetal)
            .navigationTitle("New project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showNewProject = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        let project = environment.projectStore.createProject(
                            name: name,
                            address: newAddress.isEmpty ? nil : newAddress
                        )
                        newName = ""
                        newAddress = ""
                        showNewProject = false
                        Task { await environment.pushProject(project) }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var apiText: String = ""
    @State private var contourIntervalText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Supabase") {
                    Text(SupabaseConfig.projectURL.absoluteString)
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textSecondary)
                    if let email = environment.authService.currentUser?.email {
                        Text(email)
                            .font(LiDirtTypography.caption)
                            .foregroundStyle(LiDirtColors.textMuted)
                    }
                    Button("Sync projects now") {
                        Task { await environment.syncFromCloud() }
                    }
                    if let message = environment.cloudSyncMessage {
                        Text(message)
                            .font(LiDirtTypography.caption)
                            .foregroundStyle(LiDirtColors.textMuted)
                    }
                    TextField("Legacy API base (optional)", text: $apiText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Scan HUD") {
                    Toggle("Show GPS box on scan", isOn: $environment.showScanGPSBanner)
                        .onChange(of: environment.showScanGPSBanner) { _, show in
                            environment.saveShowScanGPSBanner(show)
                        }
                    Text("Off by default. When hidden, tap the location button on the scan screen for GPS / north details.")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)
                }
                Section("Units") {
                    Picker("Units", selection: $environment.preferredUnits) {
                        ForEach(UnitsPreference.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                }
                Section("Contours") {
                    TextField("Interval (inches)", text: $contourIntervalText)
                        .keyboardType(.decimalPad)
                    Text("Used on scan review and the Contour map. Default 0.125 in (1/8 in).")
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)
                    Picker("Ground detail", selection: $environment.contourSurfaceMode) {
                        ForEach(ContourSurfaceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .onChange(of: environment.contourSurfaceMode) { _, mode in
                        environment.saveContourSurfaceMode(mode)
                    }
                    Text(environment.contourSurfaceMode.shortHelp)
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textMuted)
                }
                Section("Disclaimer") {
                    Text(ScanPackageWriter.disclaimer)
                        .font(LiDirtTypography.caption)
                    Text(GISDisclaimer.contourMap)
                        .font(LiDirtTypography.caption)
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        Task {
                            await environment.signOut()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let url = URL(string: apiText), !apiText.isEmpty {
                            environment.updateAPIBaseURL(url)
                        }
                        let cleaned = contourIntervalText.replacingOccurrences(of: ",", with: ".")
                        if let value = Double(cleaned), value > 0 {
                            environment.savePreferredContourIntervalInches(value)
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                apiText = environment.apiBaseURL.absoluteString
                contourIntervalText = String(format: "%g", environment.preferredContourIntervalInches)
            }
        }
    }
}
