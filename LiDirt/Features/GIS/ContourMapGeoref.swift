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
        return segs.enumerated().map { index, seg in
            ContourPolyline(
                id: "\(index)-\(seg.elevationM)",
                coordinates: [
                    coordinate(localXMetersEast: seg.ax, localZMetersNorth: seg.az, origin: origin),
                    coordinate(localXMetersEast: seg.bx, localZMetersNorth: seg.bz, origin: origin)
                ],
                elevationM: seg.elevationM
            )
        }
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
