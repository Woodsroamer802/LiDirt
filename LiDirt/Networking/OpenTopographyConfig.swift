import Foundation

/// Foundation DEM source for Job Site / Contour maps.
///
/// Near-term: OpenTopography (`portal.opentopography.org`) for USGS 3DEP rasters.
/// End state: self-host the same AAIGrid bbox API so the app never depends on OT rate limits
/// or embedding a third-party key. Point `FOUNDATION_DEM_URL` at your host when ready —
/// request shape stays `south/north/west/east` + `outputFormat=AAIGrid` (+ optional API key).
enum FoundationDEMConfig {
    enum Provider: String {
        /// OpenTopography USGS 3DEP proxy (`/API/usgsdem`).
        case openTopography
        /// Your hosted DEM service (OT-compatible AAIGrid bbox API).
        case selfHosted
        /// Skip raster API; sample National Map ImageServer only.
        case nationalMap
    }

    /// Info.plist `FOUNDATION_DEM_PROVIDER`: `openTopography` | `selfHosted` | `nationalMap`.
    static var provider: Provider {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "FOUNDATION_DEM_PROVIDER") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed == "selfhosted" || trimmed == "self_hosted" || trimmed == "self-hosted" {
                return .selfHosted
            }
            if trimmed == "nationalmap" || trimmed == "national_map" || trimmed == "usgs" {
                return .nationalMap
            }
            if trimmed == "opentopography" || trimmed == "opentopo" {
                return .openTopography
            }
        }
        // Default: OpenTopography until self-hosted DEM is online.
        return .openTopography
    }

    /// Override raster DEM base URL (self-host or OT). Empty → provider default.
    static var demURL: String {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "FOUNDATION_DEM_URL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        switch provider {
        case .openTopography:
            return "https://portal.opentopography.org/API/usgsdem"
        case .selfHosted:
            // Placeholder — set FOUNDATION_DEM_URL when the host is live.
            return ""
        case .nationalMap:
            return ""
        }
    }

    /// Optional API key (OT personal/Enterprise, or your self-hosted auth).
    /// Empty OT key falls back to the public demo key (rate-limited; not for production).
    static var apiKey: String {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "OPENTOPOGRAPHY_API_KEY") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let raw = Bundle.main.object(forInfoDictionaryKey: "FOUNDATION_DEM_API_KEY") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if provider == .openTopography {
            return "demoapikeyot2022"
        }
        return ""
    }

    /// USGS 3DEP product via OpenTopography. USGS1m is academic-only; USGS10m is the practical default.
    static var datasetName: String {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "FOUNDATION_DEM_DATASET") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "USGS10m"
    }

    /// Whether to try the raster bbox API (OT / self-host) before National Map multipoint.
    static var usesRasterAPI: Bool {
        switch provider {
        case .openTopography: return true
        case .selfHosted: return !demURL.isEmpty
        case .nationalMap: return false
        }
    }
}

/// Back-compat alias used by older call sites / docs.
typealias OpenTopographyConfig = FoundationDEMConfig
