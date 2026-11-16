import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    @Published var apiBaseURL: URL
    @Published var authToken: String?
    @Published var preferredUnits: UnitsPreference
    @Published var preferredContourIntervalInches: Double
    /// Resolved county / government ArcGIS FeatureServer layer URL or GeoJSON endpoint for parcel lines.
    @Published var parcelSourceURL: String
    @Published var parcelSourceTitle: String
    @Published var parcelCounty: String
    @Published var parcelState: String
    @Published var parcelZIP: String
    /// When false (default), scan HUD hides the GPS/orientation box; open it from the location button or Settings.
    @Published var showScanGPSBanner: Bool

    let projectStore: ProjectStore
    let authService: AuthService
    let uploadQueue: UploadQueue
    let localScanStore: LocalScanStore
    let tokenBox: TokenBox

    private let defaults: UserDefaults
    private static let showScanGPSBannerKey = "showScanGPSBanner"
    private static let parcelSourceTitleKey = "parcelSourceTitle"
    private static let parcelCountyKey = "parcelCounty"
    private static let parcelStateKey = "parcelState"
    private static let parcelZIPKey = "parcelZIP"

    init(
        apiBaseURL: URL = URL(string: "https://api.lidirt.example/v1")!,
        authToken: String? = nil,
        preferredUnits: UnitsPreference = .usCustomary,
        preferredContourIntervalInches: Double = 0.125,
        parcelSourceURL: String? = nil,
        showScanGPSBanner: Bool? = nil,
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
        self.parcelSourceTitle = defaults.string(forKey: Self.parcelSourceTitleKey) ?? ""
        self.parcelCounty = defaults.string(forKey: Self.parcelCountyKey) ?? ""
        self.parcelState = defaults.string(forKey: Self.parcelStateKey) ?? ""
        self.parcelZIP = defaults.string(forKey: Self.parcelZIPKey) ?? ""
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
        let client = APIClient(baseURL: apiBaseURL, tokenBox: tokenBox)
        self.uploadQueue = UploadQueue(paths: paths, uploadService: UploadService(client: client))
    }

    func saveParcelSourceURL(_ url: String, title: String? = nil) {
        parcelSourceURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(parcelSourceURL, forKey: "parcelSourceURL")
        if let title {
            parcelSourceTitle = title
            defaults.set(parcelSourceTitle, forKey: Self.parcelSourceTitleKey)
        }
    }

    func saveParcelPlace(county: String, state: String, zip: String) {
        parcelCounty = county.trimmingCharacters(in: .whitespacesAndNewlines)
        parcelState = state.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        parcelZIP = zip.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(parcelCounty, forKey: Self.parcelCountyKey)
        defaults.set(parcelState, forKey: Self.parcelStateKey)
        defaults.set(parcelZIP, forKey: Self.parcelZIPKey)
    }

    func saveParcelResolution(_ resolution: ParcelSourceResolution) {
        saveParcelPlace(county: resolution.county, state: resolution.state, zip: resolution.zip)
        saveParcelSourceURL(resolution.layerURL)
        parcelSourceTitle = resolution.title
        defaults.set(parcelSourceTitle, forKey: Self.parcelSourceTitleKey)
    }

    func clearParcelSource() {
        saveParcelSourceURL("")
        parcelSourceTitle = ""
        defaults.set("", forKey: Self.parcelSourceTitleKey)
    }

    func saveShowScanGPSBanner(_ show: Bool) {
        showScanGPSBanner = show
        defaults.set(show, forKey: Self.showScanGPSBannerKey)
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
