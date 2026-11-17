import Foundation
import CoreLocation

/// Foundation DEM for Job Site / Contour maps.
/// Raster path: OpenTopography now, self-hosted AAIGrid bbox API later (`FoundationDEMConfig`).
/// Fallback: public National Map ImageServer multipoint sampler.
enum USGSElevationServiceError: LocalizedError {
    case badURL
    case http(Int)
    case decode
    case empty
    case raster(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Could not build elevation request."
        case .http(let code): return "Elevation HTTP \(code)."
        case .decode: return "Could not read elevation samples."
        case .empty: return "No elevation samples returned for this site."
        case .raster(let message): return message
        }
    }
}

struct USGSElevationService: Sendable {
    /// Legacy National Map 3DEP elevation ImageServer (fallback).
    var nationalMapEndpoint =
        "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/getSamples"
    /// OpenTopography or self-hosted OT-compatible AAIGrid endpoint.
    var rasterEndpoint: String = FoundationDEMConfig.demURL
    var rasterDataset: String = FoundationDEMConfig.datasetName
    var apiKey: String = FoundationDEMConfig.apiKey
    var session: URLSession = .shared
    /// Max multipoint samples per National Map request.
    var batchSize = 80
    /// Prefer raster bbox API (OT / self-host) when configured.
    var preferRasterAPI: Bool = FoundationDEMConfig.usesRasterAPI

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
        return try await fetchLocalMeterGrid(
            minX: minX,
            maxX: maxX,
            minZ: minZ,
            maxZ: maxZ,
            cellSizeM: cellSizeM,
            origin: origin
        )
    }

    /// Sample elevation over a Job Site AABB (no LiDAR required) for pad-scale contour maps.
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
        let heightmap = try await fetchLocalMeterGrid(
            minX: minX0 - paddingM,
            maxX: maxX0 + paddingM,
            minZ: minZ0 - paddingM,
            maxZ: maxZ0 + paddingM,
            cellSizeM: resolvedCell,
            origin: origin
        )
        return (heightmap, origin)
    }

    private func fetchLocalMeterGrid(
        minX: Double,
        maxX: Double,
        minZ: Double,
        maxZ: Double,
        cellSizeM: Double,
        origin: CLLocationCoordinate2D
    ) async throws -> HeightmapResult {
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

        let samples: [Double?]
        if preferRasterAPI, !rasterEndpoint.isEmpty {
            do {
                let lats = points.map(\.coord.latitude)
                let lons = points.map(\.coord.longitude)
                guard let south = lats.min(), let north = lats.max(),
                      let west = lons.min(), let east = lons.max() else {
                    throw USGSElevationServiceError.empty
                }
                // Small geographic pad so edge bilinear samples stay inside the raster.
                let padDeg = max(0.0002, cellSizeM / 111_320.0)
                let grid = try await fetchRasterAAIGrid(
                    south: south - padDeg,
                    north: north + padDeg,
                    west: west - padDeg,
                    east: east + padDeg
                )
                samples = points.map { AAIGrid.sampleBilinear(grid, latitude: $0.coord.latitude, longitude: $0.coord.longitude) }
            } catch {
                // Fall back to National Map if OT / self-host is unavailable or rate-limited.
                samples = try await fetchElevations(points.map(\.coord))
            }
        } else {
            samples = try await fetchElevations(points.map(\.coord))
        }

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
            sampleCounts: [Int](repeating: 1, count: width * height),
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

    // MARK: - Raster bbox API (OpenTopography now / self-hosted later)

    /// OT-compatible request: bbox → Arc ASCII Grid. Self-host the same contract later.
    func fetchRasterAAIGrid(
        south: Double,
        north: Double,
        west: Double,
        east: Double
    ) async throws -> AAIGrid {
        guard var components = URLComponents(string: rasterEndpoint) else {
            throw USGSElevationServiceError.badURL
        }
        var items = [
            URLQueryItem(name: "south", value: String(south)),
            URLQueryItem(name: "north", value: String(north)),
            URLQueryItem(name: "west", value: String(west)),
            URLQueryItem(name: "east", value: String(east)),
            URLQueryItem(name: "outputFormat", value: "AAIGrid")
        ]
        // OpenTopography requires datasetName; self-host may ignore it.
        if !rasterDataset.isEmpty {
            items.insert(URLQueryItem(name: "datasetName", value: rasterDataset), at: 0)
        }
        if !apiKey.isEmpty {
            items.append(URLQueryItem(name: "API_Key", value: apiKey))
        }
        components.queryItems = items
        guard let url = components.url else { throw USGSElevationServiceError.badURL }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 401 || body.localizedCaseInsensitiveContains("rate limit") {
                throw USGSElevationServiceError.raster("DEM host rate limit or unauthorized — check API key / FOUNDATION_DEM_URL.")
            }
            throw USGSElevationServiceError.http(http.statusCode)
        }
        if let text = String(data: data, encoding: .utf8),
           text.contains("<error>") || text.localizedCaseInsensitiveContains("API maximum rate limit") {
            throw USGSElevationServiceError.raster(
                text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return try AAIGrid.parse(data)
    }

    // MARK: - National Map fallback

    func fetchElevations(_ coordinates: [CLLocationCoordinate2D]) async throws -> [Double?] {
        guard !coordinates.isEmpty else { return [] }
        var out = [Double?](repeating: nil, count: coordinates.count)
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
        guard var components = URLComponents(string: nationalMapEndpoint) else {
            throw USGSElevationServiceError.badURL
        }
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

// MARK: - Arc ASCII Grid (AAIGrid)

struct AAIGrid: Sendable {
    var ncols: Int
    var nrows: Int
    /// Southwest corner of the grid (cell corners).
    var xllcorner: Double
    var yllcorner: Double
    var cellsize: Double
    var nodata: Double
    /// Row-major, north → south (AAIGrid convention): index = row * ncols + col.
    var values: [Double]

    static func parse(_ data: Data) throws -> AAIGrid {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii) else {
            throw USGSElevationServiceError.decode
        }
        return try parse(text)
    }

    static func parse(_ text: String) throws -> AAIGrid {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0) }
        var ncols: Int?
        var nrows: Int?
        var xllcorner: Double?
        var yllcorner: Double?
        var cellsize: Double?
        var nodata = -9999.0
        var dataStart = 0
        var xIsCenter = false
        var yIsCenter = false
        let headerKeys: Set<String> = [
            "ncols", "nrows", "xllcorner", "yllcorner", "xllcenter", "yllcenter", "cellsize", "nodata_value"
        ]

        for (lineIndex, line) in lines.enumerated() {
            let parts = line.split { $0.isWhitespace }.map(String.init)
            guard let head = parts.first?.lowercased(), parts.count >= 2 else { continue }
            guard headerKeys.contains(head) else {
                dataStart = lineIndex
                break
            }
            switch head {
            case "ncols": ncols = Int(parts[1])
            case "nrows": nrows = Int(parts[1])
            case "xllcorner":
                xllcorner = Double(parts[1]); xIsCenter = false
            case "yllcorner":
                yllcorner = Double(parts[1]); yIsCenter = false
            case "xllcenter":
                xllcorner = Double(parts[1]); xIsCenter = true
            case "yllcenter":
                yllcorner = Double(parts[1]); yIsCenter = true
            case "cellsize": cellsize = Double(parts[1])
            case "nodata_value": nodata = Double(parts[1]) ?? nodata
            default: break
            }
            dataStart = lineIndex + 1
        }

        guard let cols = ncols, let rows = nrows, let cs = cellsize,
              var x0 = xllcorner, var y0 = yllcorner, cols > 0, rows > 0 else {
            throw USGSElevationServiceError.decode
        }
        if xIsCenter { x0 -= cs / 2 }
        if yIsCenter { y0 -= cs / 2 }

        var values: [Double] = []
        values.reserveCapacity(cols * rows)
        for line in lines[dataStart...] {
            for part in line.split(whereSeparator: \.isWhitespace) {
                if let v = Double(part) {
                    values.append(v)
                }
            }
            if values.count >= cols * rows { break }
        }
        guard values.count >= cols * rows else { throw USGSElevationServiceError.decode }
        if values.count > cols * rows {
            values = Array(values.prefix(cols * rows))
        }

        return AAIGrid(
            ncols: cols,
            nrows: rows,
            xllcorner: x0,
            yllcorner: y0,
            cellsize: cs,
            nodata: nodata,
            values: values
        )
    }

    /// Bilinear sample in WGS84. Returns nil for NODATA / outside.
    static func sampleBilinear(_ grid: AAIGrid, latitude: Double, longitude: Double) -> Double? {
        let cs = grid.cellsize
        guard cs > 0 else { return nil }
        // Pixel centers: col 0 at xll + cs/2, row 0 (north) at yll + nrows*cs - cs/2
        let colF = (longitude - grid.xllcorner) / cs - 0.5
        let rowFromSouth = (latitude - grid.yllcorner) / cs - 0.5
        let rowF = Double(grid.nrows - 1) - rowFromSouth
        if colF < -0.5 || rowF < -0.5 || colF > Double(grid.ncols) - 0.5 || rowF > Double(grid.nrows) - 0.5 {
            return nil
        }
        let c0 = max(0, min(grid.ncols - 1, Int(floor(colF))))
        let r0 = max(0, min(grid.nrows - 1, Int(floor(rowF))))
        let c1 = min(grid.ncols - 1, c0 + 1)
        let r1 = min(grid.nrows - 1, r0 + 1)
        let tx = colF - Double(c0)
        let ty = rowF - Double(r0)

        func value(row: Int, col: Int) -> Double? {
            let v = grid.values[row * grid.ncols + col]
            if v == grid.nodata || v <= -1e5 { return nil }
            return v
        }

        guard let v00 = value(row: r0, col: c0) else { return value(row: r0, col: c1) ?? value(row: r1, col: c0) }
        let v10 = value(row: r0, col: c1) ?? v00
        let v01 = value(row: r1, col: c0) ?? v00
        let v11 = value(row: r1, col: c1) ?? v10

        let a = v00 * (1 - tx) + v10 * tx
        let b = v01 * (1 - tx) + v11 * tx
        return a * (1 - ty) + b * ty
    }
}
