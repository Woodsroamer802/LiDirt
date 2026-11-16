import Foundation
import CoreLocation

struct ParcelPlaceQuery: Equatable, Sendable {
    var county: String
    var state: String
    var zip: String

    var isEmpty: Bool {
        county.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && zip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ParcelSourceResolution: Equatable, Sendable {
    var title: String
    var layerURL: String
    var county: String
    var state: String
    var zip: String
    var method: String
}

enum ParcelSourceResolveError: LocalizedError {
    case needCountyStateOrZip
    case placeNotFound
    case noPublicLayer
    case http(Int)
    case decode

    var errorDescription: String? {
        switch self {
        case .needCountyStateOrZip:
            return "Enter a ZIP code, or both county and state."
        case .placeNotFound:
            return "Could not find that place. Check county/state or ZIP."
        case .noPublicLayer:
            return "No public parcel layer found for that area. Try another spelling, or paste a custom county GIS URL."
        case .http(let code):
            return "Parcel search returned HTTP \(code)."
        case .decode:
            return "Could not read parcel search results."
        }
    }
}

protocol PlaceLookingUp: Sendable {
    func resolvePlace(query: ParcelPlaceQuery) async throws -> (county: String, state: String, zip: String)
}

/// Uses Apple geocoding so ZIP → county/state works without our own backend.
struct ApplePlaceLookup: PlaceLookingUp {
    func resolvePlace(query: ParcelPlaceQuery) async throws -> (county: String, state: String, zip: String) {
        let zip = query.zip.trimmingCharacters(in: .whitespacesAndNewlines)
        let countyIn = query.county.trimmingCharacters(in: .whitespacesAndNewlines)
        let stateIn = query.state.trimmingCharacters(in: .whitespacesAndNewlines)

        let address: String
        if !zip.isEmpty {
            address = zip
        } else if !countyIn.isEmpty && !stateIn.isEmpty {
            let countyPart = countyIn.lowercased().contains("county") ? countyIn : "\(countyIn) County"
            address = "\(countyPart), \(stateIn), USA"
        } else {
            throw ParcelSourceResolveError.needCountyStateOrZip
        }

        let geocoder = CLGeocoder()
        let marks = try await geocoder.geocodeAddressString(address)
        guard let mark = marks.first else { throw ParcelSourceResolveError.placeNotFound }

        let county = (mark.subAdministrativeArea ?? countyIn)
            .replacingOccurrences(of: " County", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let state = Self.normalizeState(mark.administrativeArea ?? stateIn)
        let resolvedZip = mark.postalCode ?? zip
        guard !county.isEmpty, !state.isEmpty else { throw ParcelSourceResolveError.placeNotFound }
        return (county, state, resolvedZip)
    }

    static func normalizeState(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 2 { return trimmed.uppercased() }
        let map: [String: String] = [
            "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR", "california": "CA",
            "colorado": "CO", "connecticut": "CT", "delaware": "DE", "florida": "FL", "georgia": "GA",
            "hawaii": "HI", "idaho": "ID", "illinois": "IL", "indiana": "IN", "iowa": "IA",
            "kansas": "KS", "kentucky": "KY", "louisiana": "LA", "maine": "ME", "maryland": "MD",
            "massachusetts": "MA", "michigan": "MI", "minnesota": "MN", "mississippi": "MS", "missouri": "MO",
            "montana": "MT", "nebraska": "NE", "nevada": "NV", "new hampshire": "NH", "new jersey": "NJ",
            "new mexico": "NM", "new york": "NY", "north carolina": "NC", "north dakota": "ND", "ohio": "OH",
            "oklahoma": "OK", "oregon": "OR", "pennsylvania": "PA", "rhode island": "RI", "south carolina": "SC",
            "south dakota": "SD", "tennessee": "TN", "texas": "TX", "utah": "UT", "vermont": "VT",
            "virginia": "VA", "washington": "WA", "west virginia": "WV", "wisconsin": "WI", "wyoming": "WY",
            "district of columbia": "DC"
        ]
        return map[trimmed.lowercased()] ?? trimmed.uppercased()
    }
}

/// Resolves a county/ZIP to a public ArcGIS FeatureServer layer URL (best-effort open data).
final class ParcelSourceResolver: Sendable {
    private let placeLookup: any PlaceLookingUp
    private let session: URLSession

    init(
        placeLookup: any PlaceLookingUp = ApplePlaceLookup(),
        session: URLSession = .shared
    ) {
        self.placeLookup = placeLookup
        self.session = session
    }

    func resolve(query: ParcelPlaceQuery) async throws -> ParcelSourceResolution {
        let place = try await placeLookup.resolvePlace(query: query)
        let candidates = try await searchArcGIS(county: place.county, state: place.state)
        guard let best = Self.pickBest(candidates: candidates, county: place.county, state: place.state) else {
            throw ParcelSourceResolveError.noPublicLayer
        }

        let layerURL = try await preferredLayerURL(featureServiceURL: best.url)
        return ParcelSourceResolution(
            title: best.title,
            layerURL: layerURL.absoluteString,
            county: place.county,
            state: place.state,
            zip: place.zip,
            method: "arcgis_search"
        )
    }

    struct SearchHit: Equatable, Sendable {
        var title: String
        var url: String
        var type: String
    }

    static func pickBest(candidates: [SearchHit], county: String, state: String) -> SearchHit? {
        let scored: [(SearchHit, Int)] = candidates.compactMap { hit in
            let title = hit.title.lowercased()
            let url = hit.url.lowercased()
            let type = hit.type.lowercased()
            guard url.contains("featureserver")
                    || url.contains("mapserver")
                    || type.contains("feature")
                    || type.contains("map") else { return nil }
            var score = 0
            if title.contains("parcel") { score += 5 }
            if title.contains("tax") { score += 2 }
            if title.contains("cadastr") { score += 2 }
            if title.contains("assessor") { score += 2 }
            if title.contains(county.lowercased()) { score += 4 }
            if title.contains(state.lowercased()) { score += 2 }
            if url.contains("parcel") { score += 2 }
            if score == 0 { return nil }
            return (hit, score)
        }
        return scored.max(by: { $0.1 < $1.1 })?.0
    }

    static func layerURLAppendingDefaultIndex(_ raw: String) -> String {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url.removeLast() }
        if url.range(of: #"/((Feature|Map)Server)/\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return url
        }
        let lower = url.lowercased()
        if lower.hasSuffix("/featureserver") || lower.hasSuffix("/mapserver") {
            return url + "/0"
        }
        return url
    }

    private func searchArcGIS(county: String, state: String) async throws -> [SearchHit] {
        var components = URLComponents(string: "https://www.arcgis.com/sharing/rest/search")
        components?.queryItems = [
            URLQueryItem(name: "f", value: "json"),
            URLQueryItem(name: "q", value: "parcel \(county) \(state)"),
            URLQueryItem(name: "filter", value: #"type:"Feature Service""#),
            URLQueryItem(name: "num", value: "25")
        ]
        guard let url = components?.url else { throw ParcelSourceResolveError.decode }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ParcelSourceResolveError.http(http.statusCode)
        }
        return try Self.decodeSearchResults(data)
    }

    static func decodeSearchResults(_ data: Data) throws -> [SearchHit] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else {
            throw ParcelSourceResolveError.decode
        }
        return results.compactMap { item in
            guard let title = item["title"] as? String,
                  let url = item["url"] as? String else { return nil }
            let type = (item["type"] as? String) ?? ""
            return SearchHit(title: title, url: url, type: type)
        }
    }

    private func preferredLayerURL(featureServiceURL: String) async throws -> URL {
        let normalized = Self.layerURLAppendingDefaultIndex(featureServiceURL)
        guard var root = URL(string: featureServiceURL) else { throw ParcelSourceResolveError.decode }

        // Strip trailing layer index for service metadata.
        if Int(root.lastPathComponent) != nil {
            root.deleteLastPathComponent()
        }

        if let metaURL = URL(string: root.absoluteString + "?f=json"),
           let (data, response) = try? await session.data(from: metaURL),
           let http = response as? HTTPURLResponse,
           (200..<300).contains(http.statusCode),
           let rootObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let layers = rootObj["layers"] as? [[String: Any]] {
            let ranked = layers.compactMap { layer -> (Int, Int)? in
                guard let id = layer["id"] as? Int else { return nil }
                let name = ((layer["name"] as? String) ?? "").lowercased()
                var score = 0
                if name.contains("parcel") { score += 5 }
                if name.contains("tax") { score += 2 }
                if name.contains("lot") { score += 1 }
                return (score, id)
            }
            if let best = ranked.max(by: { lhs, rhs in
                if lhs.0 == rhs.0 { return lhs.1 > rhs.1 }
                return lhs.0 < rhs.0
            }), best.0 > 0 {
                return root.appendingPathComponent("\(best.1)")
            }
            if let first = ranked.min(by: { $0.1 < $1.1 }) {
                return root.appendingPathComponent("\(first.1)")
            }
        }

        guard let url = URL(string: normalized) else { throw ParcelSourceResolveError.decode }
        return url
    }
}

enum USStateOption: String, CaseIterable, Identifiable {
    case AL, AK, AZ, AR, CA, CO, CT, DE, FL, GA, HI, ID, IL, IN, IA, KS, KY, LA, ME, MD
    case MA, MI, MN, MS, MO, MT, NE, NV, NH, NJ, NM, NY, NC, ND, OH, OK, OR, PA, RI, SC
    case SD, TN, TX, UT, VT, VA, WA, WV, WI, WY, DC

    var id: String { rawValue }
    var label: String { rawValue }
}
