import Foundation
import MapKit
import CoreLocation

struct ParcelPolygon: Identifiable, Equatable {
    var id: String
    var coordinates: [CLLocationCoordinate2D]
    var label: String?

    static func == (lhs: ParcelPolygon, rhs: ParcelPolygon) -> Bool {
        lhs.id == rhs.id
    }
}

enum ParcelLoadError: LocalizedError {
    case invalidURL
    case empty
    case http(Int)
    case decode

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Parcel source URL is invalid."
        case .empty: return "No parcel polygons in this map area."
        case .http(let code): return "Parcel source returned HTTP \(code)."
        case .decode: return "Could not decode parcel GeoJSON."
        }
    }
}

/// Loads parcel / boundary polygons from a public ArcGIS FeatureServer query or raw GeoJSON URL.
final class ParcelBoundaryService: Sendable {
    func fetchParcels(
        sourceURLString: String,
        region: MKCoordinateRegion
    ) async throws -> [ParcelPolygon] {
        let trimmed = sourceURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let base = URL(string: trimmed) else {
            throw ParcelLoadError.invalidURL
        }

        let queryURL: URL
        if trimmed.lowercased().contains("/query") || trimmed.lowercased().hasSuffix(".json") || trimmed.lowercased().contains("geojson") {
            queryURL = base
        } else {
            // Treat as FeatureServer layer root → append query for current map envelope.
            queryURL = try makeArcGISQueryURL(layerBase: base, region: region)
        }

        let (data, response) = try await URLSession.shared.data(from: queryURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ParcelLoadError.http(http.statusCode)
        }

        let polygons = try decodeGeoJSONPolygons(data)
        if polygons.isEmpty { throw ParcelLoadError.empty }
        return polygons
    }

    /// Distance in meters from a point to the nearest polygon edge (rough planar estimate).
    func nearestBoundaryDistanceMeters(
        from coordinate: CLLocationCoordinate2D,
        polygons: [ParcelPolygon]
    ) -> Double? {
        var best: Double?
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        for poly in polygons {
            guard poly.coordinates.count >= 2 else { continue }
            for i in 0..<(poly.coordinates.count - 1) {
                let a = poly.coordinates[i]
                let b = poly.coordinates[i + 1]
                let mid = CLLocation(
                    latitude: (a.latitude + b.latitude) / 2,
                    longitude: (a.longitude + b.longitude) / 2
                )
                let d = origin.distance(from: mid)
                if best == nil || d < best! { best = d }
            }
        }
        return best
    }

    private func makeArcGISQueryURL(layerBase: URL, region: MKCoordinateRegion) throws -> URL {
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let geometry = "\(minLon),\(minLat),\(maxLon),\(maxLat)"

        var components = URLComponents(
            url: layerBase.appendingPathComponent("query"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "f", value: "geojson"),
            URLQueryItem(name: "where", value: "1=1"),
            URLQueryItem(name: "geometry", value: geometry),
            URLQueryItem(name: "geometryType", value: "esriGeometryEnvelope"),
            URLQueryItem(name: "inSR", value: "4326"),
            URLQueryItem(name: "spatialRel", value: "esriSpatialRelIntersects"),
            URLQueryItem(name: "outFields", value: "*"),
            URLQueryItem(name: "returnGeometry", value: "true"),
            URLQueryItem(name: "outSR", value: "4326")
        ]
        guard let url = components?.url else { throw ParcelLoadError.invalidURL }
        return url
    }

    private func decodeGeoJSONPolygons(_ data: Data) throws -> [ParcelPolygon] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else {
            throw ParcelLoadError.decode
        }

        var result: [ParcelPolygon] = []
        for (index, feature) in features.enumerated() {
            let props = feature["properties"] as? [String: Any]
            let label = (props?["OWNER"] as? String)
                ?? (props?["owner"] as? String)
                ?? (props?["NAME"] as? String)
                ?? (props?["name"] as? String)
                ?? (props?["PARCELID"] as? String)
                ?? (props?["parcel_id"] as? String)

            guard let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String else { continue }

            let rings: [[[NSNumber]]]
            if type == "Polygon", let coords = geometry["coordinates"] as? [[[NSNumber]]] {
                rings = coords
            } else if type == "MultiPolygon",
                      let multi = geometry["coordinates"] as? [[[[NSNumber]]]] {
                rings = multi.flatMap { $0 }
            } else {
                continue
            }

            for (ringIndex, ring) in rings.enumerated() {
                let coords: [CLLocationCoordinate2D] = ring.compactMap { pair in
                    guard pair.count >= 2 else { return nil }
                    return CLLocationCoordinate2D(
                        latitude: pair[1].doubleValue,
                        longitude: pair[0].doubleValue
                    )
                }
                guard coords.count >= 3 else { continue }
                result.append(
                    ParcelPolygon(
                        id: "\(index)-\(ringIndex)",
                        coordinates: coords,
                        label: label
                    )
                )
            }
        }
        return result
    }
}
