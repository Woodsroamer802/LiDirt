import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showNewProject = false
    @State private var newName = ""
    @State private var newAddress = ""
    @State private var showSettings = false

    var body: some View {
        List {
            Section {
                deviceBanner
            }
            .listRowBackground(LiDirtColors.gunmetalElevated)

            Section("Projects") {
                if environment.projectStore.projects.isEmpty {
                    Text("No projects yet. Create one to start a field scan.")
                        .foregroundStyle(LiDirtColors.textSecondary)
                        .listRowBackground(LiDirtColors.gunmetalElevated)
                }
                ForEach(environment.projectStore.projects) { project in
                    NavigationLink(value: project.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name)
                                .font(LiDirtTypography.headline)
                                .foregroundStyle(LiDirtColors.textPrimary)
                            Text("\(project.scanSummaries.count) scans")
                                .font(LiDirtTypography.caption)
                                .foregroundStyle(LiDirtColors.textMuted)
                        }
                    }
                    .listRowBackground(LiDirtColors.gunmetalElevated)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .navigationTitle("LiDirt")
        .navigationDestination(for: UUID.self) { id in
            if let project = environment.projectStore.project(id: id) {
                ProjectDetailView(projectId: project.id)
            }
        }
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
        .task {
            await environment.uploadQueue.processAll()
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
        }
        .padding(.vertical, 4)
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
                        _ = environment.projectStore.createProject(
                            name: name,
                            address: newAddress.isEmpty ? nil : newAddress
                        )
                        newName = ""
                        newAddress = ""
                        showNewProject = false
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

    var body: some View {
        NavigationStack {
            Form {
                Section("API") {
                    TextField("Base URL", text: $apiText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Default uses local stub acceptance when host is api.lidirt.example.")
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
                    Text("Preferred interval: \(environment.preferredContourIntervalInches) in (1/8 in default)")
                        .foregroundStyle(LiDirtColors.textSecondary)
                }
                Section("Disclaimer") {
                    Text(ScanPackageWriter.disclaimer)
                        .font(LiDirtTypography.caption)
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        environment.applyAuthToken(nil)
                        dismiss()
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
                        dismiss()
                    }
                }
            }
            .onAppear { apiText = environment.apiBaseURL.absoluteString }
        }
    }
}
