import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    @Published var apiBaseURL: URL
    @Published var authToken: String?
    @Published var preferredUnits: UnitsPreference
    @Published var preferredContourIntervalInches: Double
    /// Contour surface: as-scanned texture vs smoothed ground (ignore gravel / veg / tire chew).
    @Published var contourSurfaceMode: ContourSurfaceMode
    /// When false (default), scan HUD hides the GPS/orientation box; open it from the location button or Settings.
    @Published var showScanGPSBanner: Bool
    @Published var cloudSyncMessage: String?

    let projectStore: ProjectStore
    let authService: AuthService
    let uploadQueue: UploadQueue
    let localScanStore: LocalScanStore
    let tokenBox: TokenBox

    private let defaults: UserDefaults
    private static let showScanGPSBannerKey = "showScanGPSBanner"
    private static let contourIntervalKey = "preferredContourIntervalInches"
    private static let contourSurfaceModeKey = "contourSurfaceMode"

    init(
        apiBaseURL: URL = SupabaseConfig.projectURL,
        authToken: String? = nil,
        preferredUnits: UnitsPreference = .usCustomary,
        preferredContourIntervalInches: Double? = nil,
        contourSurfaceMode: ContourSurfaceMode? = nil,
        showScanGPSBanner: Bool? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.apiBaseURL = apiBaseURL
        self.authToken = authToken
        self.preferredUnits = preferredUnits
        if let preferredContourIntervalInches {
            self.preferredContourIntervalInches = preferredContourIntervalInches
        } else if defaults.object(forKey: Self.contourIntervalKey) != nil {
            let stored = defaults.double(forKey: Self.contourIntervalKey)
            self.preferredContourIntervalInches = stored > 0 ? stored : ContourPreview.defaultIntervalInches
        } else {
            self.preferredContourIntervalInches = ContourPreview.defaultIntervalInches
        }
        if let contourSurfaceMode {
            self.contourSurfaceMode = contourSurfaceMode
        } else if let raw = defaults.string(forKey: Self.contourSurfaceModeKey),
                  let mode = ContourSurfaceMode(rawValue: raw) {
            self.contourSurfaceMode = mode
        } else {
            self.contourSurfaceMode = .smoothedGround
        }
        if let showScanGPSBanner {
            self.showScanGPSBanner = showScanGPSBanner
        } else if defaults.object(forKey: Self.showScanGPSBannerKey) != nil {
            self.showScanGPSBanner = defaults.bool(forKey: Self.showScanGPSBannerKey)
        } else {
            self.showScanGPSBanner = false
        }

        let paths = FilePaths.shared
        let tokenBox = TokenBox(authToken)
        self.tokenBox = tokenBox
        self.localScanStore = LocalScanStore(paths: paths)
        self.projectStore = ProjectStore(paths: paths)
        self.authService = AuthService()
        let client = APIClient(baseURL: apiBaseURL, tokenBox: tokenBox, useLocalStub: false)
        self.uploadQueue = UploadQueue(paths: paths, uploadService: UploadService(client: client))
    }

    func savePreferredContourIntervalInches(_ inches: Double) {
        preferredContourIntervalInches = max(inches, 0.01)
        defaults.set(preferredContourIntervalInches, forKey: Self.contourIntervalKey)
    }

    func saveContourSurfaceMode(_ mode: ContourSurfaceMode) {
        contourSurfaceMode = mode
        defaults.set(mode.rawValue, forKey: Self.contourSurfaceModeKey)
    }

    func saveShowScanGPSBanner(_ show: Bool) {
        showScanGPSBanner = show
        defaults.set(show, forKey: Self.showScanGPSBannerKey)
    }

    func applyAuthToken(_ token: String?) {
        authToken = token
        tokenBox.set(token)
        uploadQueue.updateClient(APIClient(baseURL: apiBaseURL, tokenBox: tokenBox, useLocalStub: false))
    }

    func updateAPIBaseURL(_ url: URL) {
        apiBaseURL = url
        uploadQueue.updateClient(APIClient(baseURL: url, tokenBox: tokenBox, useLocalStub: false))
    }

    /// Pull projects + scans from Supabase into the local store (keeps local package paths).
    func syncFromCloud() async {
        guard authToken != nil else { return }
        do {
            let remote = try await SupabaseClient.shared.fetchProjects()
            projectStore.replaceFromRemote(remote)
            cloudSyncMessage = "Synced \(remote.count) project(s) from Supabase."
        } catch {
            cloudSyncMessage = "Cloud sync failed: \(error.localizedDescription)"
        }
    }

    /// Push one project row (and keep going offline-first if it fails).
    func pushProject(_ project: Project) async {
        guard let ownerId = authService.currentUser?.id ?? (await SupabaseClient.shared.currentSession())?.userId else {
            return
        }
        do {
            try await SupabaseClient.shared.upsertProject(project, ownerId: ownerId)
        } catch {
            cloudSyncMessage = "Project saved locally; cloud push failed: \(error.localizedDescription)"
        }
    }

    func signOut() async {
        await authService.logout()
        applyAuthToken(nil)
    }
}

enum UnitsPreference: String, Codable, CaseIterable, Identifiable {
    case usCustomary
    case metric

    var id: String { rawValue }

    var label: String {
        switch self {
        case .usCustomary: return "ft / in"
        case .metric: return "m / cm"
        }
    }
}
