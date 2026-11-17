import Foundation
import CoreLocation

/// OpenStreetMap building outline for Job Site map shading.
struct BuildingFootprint: Identifiable, Equatable, Sendable {
    var id: String
    var coordinates: [CLLocationCoordinate2D]
    /// OSM `building=*` value when present (e.g. house, industrial).
    var kind: String?

    static func == (lhs: BuildingFootprint, rhs: BuildingFootprint) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.coordinates.count == rhs.coordinates.count
            && zip(lhs.coordinates, rhs.coordinates).allSatisfy {
                $0.0.latitude == $0.1.latitude && $0.0.longitude == $0.1.longitude
            }
    }
}

enum BuildingFootprintServiceError: LocalizedError {
    case badURL
    case http(Int)
    case decode
    case emptyQuery

    var errorDescription: String? {
        switch self {
        case .badURL: return "Could not build building footprint request."
        case .http(let code): return "Building footprint HTTP \(code)."
        case .decode: return "Could not read building footprints."
        case .emptyQuery: return "Job Site bounds are invalid for building lookup."
        }
    }
}

/// Fetches building polygons from OpenStreetMap via Overpass (public data).
struct BuildingFootprintService: Sendable {
    /// Prefer mirrors that accept anonymous POSTs; fall through on failure.
    var endpoints: [String] = [
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter"
    ]
    var session: URLSession = .shared
    /// Cap how many footprints we keep for a pad (keeps MapKit responsive).
    var maxBuildings = 400

    func fetchBuildings(
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        padDegrees: Double = 0.00015
    ) async throws -> [BuildingFootprint] {
        guard south < north, west < east else { throw BuildingFootprintServiceError.emptyQuery }
        let s = south - padDegrees
        let n = north + padDegrees
        let w = west - padDegrees
        let e = east + padDegrees
        // Overpass bbox order: south,west,north,east
        let query = """
        [out:json][timeout:25];
        (
          way["building"](\(s),\(w),\(n),\(e));
          relation["building"](\(s),\(w),\(n),\(e));
        );
        out geom;
        """

        var lastError: Error = BuildingFootprintServiceError.badURL
        for endpoint in endpoints {
            do {
                let data = try await post(query: query, endpoint: endpoint)
                return try Self.decode(data, maxBuildings: maxBuildings)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func fetchBuildings(covering bounds: JobSiteBounds) async throws -> [BuildingFootprint] {
        guard bounds.isValid else { throw BuildingFootprintServiceError.emptyQuery }
        return try await fetchBuildings(
            south: bounds.south,
            west: bounds.west,
            north: bounds.north,
            east: bounds.east
        )
    }

    private func post(query: String, endpoint: String) async throws -> Data {
        guard let url = URL(string: endpoint) else { throw BuildingFootprintServiceError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("LiDirt/1.0 (job-site building footprints; contact via app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = "data=" + (query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)
        request.httpBody = Data(body.utf8)
        request.timeoutInterval = 45

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BuildingFootprintServiceError.http(http.statusCode)
        }
        return data
    }

    static func decode(_ data: Data, maxBuildings: Int = 400) throws -> [BuildingFootprint] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else {
            throw BuildingFootprintServiceError.decode
        }

        var out: [BuildingFootprint] = []
        out.reserveCapacity(min(elements.count, maxBuildings))

        for element in elements {
            guard out.count < maxBuildings else { break }
            let type = element["type"] as? String
            let idNum = element["id"] as? Int ?? (element["id"] as? NSNumber)?.intValue
            let kind = (element["tags"] as? [String: Any])?["building"] as? String

            if type == "way", let geometry = element["geometry"] as? [[String: Any]] {
                let coords = Self.coordinates(from: geometry)
                guard coords.count >= 3 else { continue }
                let id = "way-\(idNum ?? out.count)"
                out.append(BuildingFootprint(id: id, coordinates: coords, kind: kind))
                continue
            }

            // Multipolygon relations: use the outer member rings that include geometry.
            if type == "relation", let members = element["members"] as? [[String: Any]] {
                for (memberIndex, member) in members.enumerated() {
                    guard out.count < maxBuildings else { break }
                    let role = (member["role"] as? String) ?? "outer"
                    guard role == "outer" || role.isEmpty else { continue }
                    guard let geometry = member["geometry"] as? [[String: Any]] else { continue }
                    let coords = Self.coordinates(from: geometry)
                    guard coords.count >= 3 else { continue }
                    let id = "rel-\(idNum ?? out.count)-outer-\(memberIndex)"
                    out.append(BuildingFootprint(id: id, coordinates: coords, kind: kind))
                }
            }
        }
        return out
    }

    private static func coordinates(from geometry: [[String: Any]]) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(geometry.count)
        for point in geometry {
            let lat = (point["lat"] as? Double) ?? (point["lat"] as? NSNumber)?.doubleValue
            let lon = (point["lon"] as? Double) ?? (point["lon"] as? NSNumber)?.doubleValue
            guard let lat, let lon else { continue }
            coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        // Ensure closed ring for MapKit fill.
        if let first = coords.first, let last = coords.last,
           first.latitude != last.latitude || first.longitude != last.longitude {
            coords.append(first)
        }
        return coords
    }
}
