import Foundation
import CoreLocation
import MapKit

/// Places LiDAR DEM contours on a map using phone GPS as the AR world origin.
/// Approximate (meters-class GNSS) — for field planning, not a certified survey.
enum ContourMapGeoref {
    struct ContourPolyline: Equatable, Identifiable, Sendable {
        var id: String
        var coordinates: [CLLocationCoordinate2D]
        var elevationM: Double

        static func == (lhs: ContourPolyline, rhs: ContourPolyline) -> Bool {
            lhs.id == rhs.id
                && lhs.elevationM == rhs.elevationM
                && lhs.coordinates.count == rhs.coordinates.count
                && zip(lhs.coordinates, rhs.coordinates).allSatisfy {
                    $0.0.latitude == $0.1.latitude && $0.0.longitude == $0.1.longitude
                }
        }
    }

    /// Convert local DEM meters (+X east, +Z north when north-aligned) to WGS84.
    static func coordinate(
        localXMetersEast: Double,
        localZMetersNorth: Double,
        origin: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        let metersPerDegLat = 111_320.0
        let latRad = origin.latitude * .pi / 180.0
        let metersPerDegLon = max(metersPerDegLat * cos(latRad), 1e-6)
        return CLLocationCoordinate2D(
            latitude: origin.latitude + localZMetersNorth / metersPerDegLat,
            longitude: origin.longitude + localXMetersEast / metersPerDegLon
        )
    }

    /// Inverse of `coordinate` — WGS84 to local meters east / north of GPS origin.
    static func localMeters(
        coordinate: CLLocationCoordinate2D,
        origin: CLLocationCoordinate2D
    ) -> (x: Double, z: Double) {
        let metersPerDegLat = 111_320.0
        let latRad = origin.latitude * .pi / 180.0
        let metersPerDegLon = max(metersPerDegLat * cos(latRad), 1e-6)
        return (
            x: (coordinate.longitude - origin.longitude) * metersPerDegLon,
            z: (coordinate.latitude - origin.latitude) * metersPerDegLat
        )
    }

    static func polylines(
        heightmap: HeightmapResult,
        origin: CLLocationCoordinate2D,
        intervalInches: Double,
        maxLevels: Int = 80
    ) -> [ContourPolyline] {
        let intervalM = intervalInches * 0.0254
        let segs = ContourPreview.localSegments(
            heightmap: heightmap,
            intervalM: intervalM,
            maxLevels: maxLevels
        )
        // Chain cell-edge segments into longer polylines so MapKit gets dozens of
        // overlays instead of thousands of 2-point lines (major scan→map lag source).
        return chain(segments: segs, origin: origin)
    }

    /// Stitch collinear-adjacent marching-squares segments per elevation level.
    static func chain(
        segments: [LocalContourSegment],
        origin: CLLocationCoordinate2D,
        joinEpsilonM: Double = 1e-4
    ) -> [ContourPolyline] {
        guard !segments.isEmpty else { return [] }
        var byLevel: [Double: [LocalContourSegment]] = [:]
        for seg in segments {
            byLevel[seg.elevationM, default: []].append(seg)
        }

        var out: [ContourPolyline] = []
        out.reserveCapacity(byLevel.count)
        for (level, levelSegs) in byLevel.sorted(by: { $0.key < $1.key }) {
            let chains = stitch(levelSegs, epsilon: joinEpsilonM)
            for (chainIndex, points) in chains.enumerated() where points.count >= 2 {
                let coords = points.map {
                    coordinate(localXMetersEast: $0.x, localZMetersNorth: $0.z, origin: origin)
                }
                out.append(ContourPolyline(
                    id: String(format: "%.6f-%d-%d", level, chainIndex, coords.count),
                    coordinates: coords,
                    elevationM: level
                ))
            }
        }
        return out
    }

    private struct LocalPoint: Hashable {
        var x: Double
        var z: Double

        init(_ x: Double, _ z: Double) {
            self.x = x
            self.z = z
        }

        func bucket(_ epsilon: Double) -> LocalPoint {
            LocalPoint(
                (x / epsilon).rounded() * epsilon,
                (z / epsilon).rounded() * epsilon
            )
        }
    }

    private static func stitch(
        _ segments: [LocalContourSegment],
        epsilon: Double
    ) -> [[LocalPoint]] {
        var adjacency: [LocalPoint: [LocalPoint]] = [:]
        adjacency.reserveCapacity(segments.count * 2)
        for seg in segments {
            let a = LocalPoint(seg.ax, seg.az).bucket(epsilon)
            let b = LocalPoint(seg.bx, seg.bz).bucket(epsilon)
            guard a != b else { continue }
            adjacency[a, default: []].append(b)
            adjacency[b, default: []].append(a)
        }

        var visited = Set<LocalPoint>()
        var chains: [[LocalPoint]] = []

        func walk(from start: LocalPoint, excluding: LocalPoint?) -> [LocalPoint] {
            var path: [LocalPoint] = [start]
            var current = start
            var previous = excluding
            while true {
                visited.insert(current)
                let neighbors = adjacency[current] ?? []
                let next = neighbors.first { candidate in
                    if let previous, candidate == previous { return false }
                    return !visited.contains(candidate) || candidate == start
                }
                guard let next, next != start else { break }
                if visited.contains(next) { break }
                path.append(next)
                previous = current
                current = next
            }
            return path
        }

        // Prefer starting at endpoints (degree 1) so open contours stay open.
        let endpoints = adjacency.keys.filter { (adjacency[$0]?.count ?? 0) == 1 }
        for start in endpoints where !visited.contains(start) {
            chains.append(walk(from: start, excluding: nil))
        }
        for start in adjacency.keys where !visited.contains(start) {
            chains.append(walk(from: start, excluding: nil))
        }
        return chains
    }

    /// Bounding region that fits the DEM footprint around the GPS origin.
    static func region(
        heightmap: HeightmapResult,
        origin: CLLocationCoordinate2D,
        paddingFactor: Double = 1.35
    ) -> MKCoordinateRegion {
        let corners = [
            coordinate(localXMetersEast: heightmap.bounds.minX, localZMetersNorth: heightmap.bounds.minZ, origin: origin),
            coordinate(localXMetersEast: heightmap.bounds.maxX, localZMetersNorth: heightmap.bounds.minZ, origin: origin),
            coordinate(localXMetersEast: heightmap.bounds.minX, localZMetersNorth: heightmap.bounds.maxZ, origin: origin),
            coordinate(localXMetersEast: heightmap.bounds.maxX, localZMetersNorth: heightmap.bounds.maxZ, origin: origin)
        ]
        let lats = corners.map(\.latitude)
        let lons = corners.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion(center: origin, span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002))
        }
        let latDelta = max((maxLat - minLat) * paddingFactor, 0.0004)
        let lonDelta = max((maxLon - minLon) * paddingFactor, 0.0004)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}
