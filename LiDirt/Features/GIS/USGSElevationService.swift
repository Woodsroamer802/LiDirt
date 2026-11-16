import Foundation
import CoreLocation

/// Samples USGS 3DEP elevations (public National Map ImageServer) into a local-meter DEM grid.
enum USGSElevationServiceError: LocalizedError {
    case badURL
    case http(Int)
    case decode
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL: return "Could not build USGS elevation request."
        case .http(let code): return "USGS elevation HTTP \(code)."
        case .decode: return "Could not read USGS elevation samples."
        case .empty: return "No USGS elevation samples returned for this site."
        }
    }
}

struct USGSElevationService: Sendable {
    /// National Map 3DEP elevation ImageServer.
    var endpoint =
        "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/getSamples"
    var session: URLSession = .shared
    /// Max multipoint samples per request.
    var batchSize = 80

    /// Build a coarse foundation heightmap in the same local (+X east / +Z north) frame as the LiDAR DEM.
    func fetchFoundationDEM(
        covering lidar: HeightmapResult,
        origin: CLLocationCoordinate2D,
        cellSizeM: Double = 2.0,
        paddingM: Double = 12.0
    ) async throws -> HeightmapResult {
        let minX = lidar.bounds.minX - paddingM
        let maxX = lidar.bounds.maxX + paddingM
        let minZ = lidar.bounds.minZ - paddingM
        let maxZ = lidar.bounds.maxZ + paddingM
        let width = max(2, Int(ceil((maxX - minX) / cellSizeM)))
        let height = max(2, Int(ceil((maxZ - minZ) / cellSizeM)))

        var points: [(col: Int, row: Int, coord: CLLocationCoordinate2D)] = []
        points.reserveCapacity(width * height)
        for row in 0..<height {
            for col in 0..<width {
                let x = minX + (Double(col) + 0.5) * cellSizeM
                let z = minZ + (Double(row) + 0.5) * cellSizeM
                let coord = ContourMapGeoref.coordinate(
                    localXMetersEast: x,
                    localZMetersNorth: z,
                    origin: origin
                )
                points.append((col, row, coord))
            }
        }

        let samples = try await fetchElevations(points.map(\.coord))
        guard samples.count == points.count else { throw USGSElevationServiceError.empty }

        var elevations = [Float](repeating: .nan, count: width * height)
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        var valid = 0
        for (i, point) in points.enumerated() {
            guard let value = samples[i] else { continue }
            elevations[point.row * width + point.col] = Float(value)
            minY = min(minY, value)
            maxY = max(maxY, value)
            valid += 1
        }
        guard valid > 0 else { throw USGSElevationServiceError.empty }

        return HeightmapResult(
            elevations: elevations,
            width: width,
            height: height,
            cellSizeM: cellSizeM,
            originX: minX,
            originZ: minZ,
            sampleCounts: [Int](repeating: valid > 0 ? 1 : 0, count: width * height),
            filledFlags: [Bool](repeating: false, count: width * height),
            bounds: HeightmapBounds(
                minX: minX,
                maxX: minX + Double(width) * cellSizeM,
                minZ: minZ,
                maxZ: minZ + Double(height) * cellSizeM,
                minY: minY,
                maxY: maxY
            )
        )
    }

    /// Sample 3DEP over a Job Site AABB (no LiDAR required) for pad-scale contour maps.
    func fetchFoundationDEM(
        covering bounds: JobSiteBounds,
        cellSizeM: Double? = nil,
        paddingM: Double = 6.0
    ) async throws -> (heightmap: HeightmapResult, origin: CLLocationCoordinate2D) {
        guard bounds.isValid else { throw USGSElevationServiceError.empty }
        let origin = bounds.center
        let corners = [
            CLLocationCoordinate2D(latitude: bounds.north, longitude: bounds.west),
            CLLocationCoordinate2D(latitude: bounds.north, longitude: bounds.east),
            CLLocationCoordinate2D(latitude: bounds.south, longitude: bounds.west),
            CLLocationCoordinate2D(latitude: bounds.south, longitude: bounds.east)
        ]
        let locals = corners.map { ContourMapGeoref.localMeters(coordinate: $0, origin: origin) }
        guard let minX0 = locals.map(\.x).min(),
              let maxX0 = locals.map(\.x).max(),
              let minZ0 = locals.map(\.z).min(),
              let maxZ0 = locals.map(\.z).max() else {
            throw USGSElevationServiceError.empty
        }
        let sideM = max(maxX0 - minX0, maxZ0 - minZ0, 1)
        let resolvedCell = cellSizeM ?? min(2.0, max(0.5, sideM / 48))
        let minX = minX0 - paddingM
        let maxX = maxX0 + paddingM
        let minZ = minZ0 - paddingM
        let maxZ = maxZ0 + paddingM
        let width = max(2, Int(ceil((maxX - minX) / resolvedCell)))
        let height = max(2, Int(ceil((maxZ - minZ) / resolvedCell)))

        var points: [(col: Int, row: Int, coord: CLLocationCoordinate2D)] = []
        points.reserveCapacity(width * height)
        for row in 0..<height {
            for col in 0..<width {
                let x = minX + (Double(col) + 0.5) * resolvedCell
                let z = minZ + (Double(row) + 0.5) * resolvedCell
                let coord = ContourMapGeoref.coordinate(
                    localXMetersEast: x,
                    localZMetersNorth: z,
                    origin: origin
                )
                points.append((col, row, coord))
            }
        }

        let samples = try await fetchElevations(points.map(\.coord))
        guard samples.count == points.count else { throw USGSElevationServiceError.empty }

        var elevations = [Float](repeating: .nan, count: width * height)
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        var valid = 0
        for (i, point) in points.enumerated() {
            guard let value = samples[i] else { continue }
            elevations[point.row * width + point.col] = Float(value)
            minY = min(minY, value)
            maxY = max(maxY, value)
            valid += 1
        }
        guard valid > 0 else { throw USGSElevationServiceError.empty }

        let heightmap = HeightmapResult(
            elevations: elevations,
            width: width,
            height: height,
            cellSizeM: resolvedCell,
            originX: minX,
            originZ: minZ,
            sampleCounts: [Int](repeating: 1, count: width * height),
            filledFlags: [Bool](repeating: false, count: width * height),
            bounds: HeightmapBounds(
                minX: minX,
                maxX: minX + Double(width) * resolvedCell,
                minZ: minZ,
                maxZ: minZ + Double(height) * resolvedCell,
                minY: minY,
                maxY: maxY
            )
        )
        return (heightmap, origin)
    }

    func fetchElevations(_ coordinates: [CLLocationCoordinate2D]) async throws -> [Double?] {
        guard !coordinates.isEmpty else { return [] }
        var out = [Double?](repeating: nil, count: coordinates.count)
        // Parallel batches — sequential USGS calls were a major scan→map delay.
        try await withThrowingTaskGroup(of: (Int, [Double?]).self) { group in
            var start = 0
            while start < coordinates.count {
                let end = min(start + batchSize, coordinates.count)
                let batch = Array(coordinates[start..<end])
                let batchStart = start
                group.addTask {
                    let values = try await self.fetchBatch(batch)
                    return (batchStart, values)
                }
                start = end
            }
            for try await (batchStart, values) in group {
                for (offset, value) in values.enumerated() {
                    out[batchStart + offset] = value
                }
            }
        }
        return out
    }

    private func fetchBatch(_ coordinates: [CLLocationCoordinate2D]) async throws -> [Double?] {
        let pointsJSON = coordinates.map { "[\($0.longitude),\($0.latitude)]" }.joined(separator: ",")
        let geometry = "{\"points\":[\(pointsJSON)],\"spatialReference\":{\"wkid\":4326}}"
        guard var components = URLComponents(string: endpoint) else { throw USGSElevationServiceError.badURL }
        components.queryItems = [
            URLQueryItem(name: "geometry", value: geometry),
            URLQueryItem(name: "geometryType", value: "esriGeometryMultipoint"),
            URLQueryItem(name: "returnFirstValueOnly", value: "true"),
            URLQueryItem(name: "f", value: "json")
        ]
        guard let url = components.url else { throw USGSElevationServiceError.badURL }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw USGSElevationServiceError.http(http.statusCode)
        }
        return try Self.decodeSamples(data, expectedCount: coordinates.count)
    }

    static func decodeSamples(_ data: Data, expectedCount: Int) throws -> [Double?] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = root["samples"] as? [[String: Any]] else {
            throw USGSElevationServiceError.decode
        }
        var byID: [Int: Double] = [:]
        for sample in samples {
            let id = (sample["locationId"] as? Int)
                ?? (sample["locationId"] as? NSNumber)?.intValue
                ?? -1
            let raw = sample["value"]
            let value: Double?
            if let number = raw as? Double {
                value = number
            } else if let number = raw as? NSNumber {
                value = number.doubleValue
            } else if let string = raw as? String {
                value = Double(string)
            } else {
                value = nil
            }
            if let value, id >= 0 {
                byID[id] = value
            }
        }
        return (0..<expectedCount).map { byID[$0] }
    }
}
