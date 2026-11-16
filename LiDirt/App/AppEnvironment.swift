import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    @Published var apiBaseURL: URL
    @Published var authToken: String?
    @Published var preferredUnits: UnitsPreference
    @Published var preferredContourIntervalInches: Double
    /// County / government ArcGIS FeatureServer layer URL or GeoJSON endpoint for parcel lines.
    @Published var parcelSourceURL: String

    let projectStore: ProjectStore
    let authService: AuthService
    let uploadQueue: UploadQueue
    let localScanStore: LocalScanStore
    let tokenBox: TokenBox

    private let defaults: UserDefaults

    init(
        apiBaseURL: URL = URL(string: "https://api.lidirt.example/v1")!,
        authToken: String? = nil,
        preferredUnits: UnitsPreference = .usCustomary,
        preferredContourIntervalInches: Double = 0.125,
        parcelSourceURL: String? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.apiBaseURL = apiBaseURL
        self.authToken = authToken
        self.preferredUnits = preferredUnits
        self.preferredContourIntervalInches = preferredContourIntervalInches
        self.parcelSourceURL = parcelSourceURL
            ?? defaults.string(forKey: "parcelSourceURL")
            ?? ""

        let paths = FilePaths.shared
        let tokenBox = TokenBox(authToken)
        self.tokenBox = tokenBox
        self.localScanStore = LocalScanStore(paths: paths)
        self.projectStore = ProjectStore(paths: paths)
        self.authService = AuthService()
        let client = APIClient(baseURL: apiBaseURL, tokenBox: tokenBox)
        self.uploadQueue = UploadQueue(paths: paths, uploadService: UploadService(client: client))
    }

    func saveParcelSourceURL(_ url: String) {
        parcelSourceURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(parcelSourceURL, forKey: "parcelSourceURL")
    }

    func applyAuthToken(_ token: String?) {
        authToken = token
        tokenBox.set(token)
        uploadQueue.updateClient(APIClient(baseURL: apiBaseURL, tokenBox: tokenBox))
    }

    func updateAPIBaseURL(_ url: URL) {
        apiBaseURL = url
        uploadQueue.updateClient(APIClient(baseURL: url, tokenBox: tokenBox))
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
