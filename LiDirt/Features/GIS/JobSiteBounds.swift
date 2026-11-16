import Foundation
import CoreLocation
import MapKit

/// Shared Job Site outline / download size defaults (feet on a side for a square).
enum JobSiteDefaults {
    /// ~10×10 ft — about 100 sq ft pad.
    static let minSideFeet: Double = 10
    static let maxSideFeet: Double = 1_000
    /// Sensible starting outline; user can shrink before download.
    static let defaultSideFeet: Double = 100

    static func clampSideFeet(_ feet: Double) -> Double {
        min(max(feet, minSideFeet), maxSideFeet)
    }

    static func halfSideMeters(sideFeet: Double) -> Double {
        (clampSideFeet(sideFeet) * 0.3048) / 2.0
    }
}

/// Axis-aligned geographic rectangle defining the on-phone Job Site focus area.
struct JobSiteBounds: Codable, Equatable, Sendable, Hashable {
    var north: Double
    var south: Double
    var east: Double
    var west: Double

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (north + south) / 2,
            longitude: (east + west) / 2
        )
    }

    var latitudeDelta: Double { max(north - south, 1e-6) }
    var longitudeDelta: Double { max(east - west, 1e-6) }

    /// Approximate north–south side length in feet.
    var sideFeetNS: Double { latitudeDelta * 364_000 }

    /// Approximate east–west side length in feet (accounts for latitude).
    var sideFeetEW: Double {
        longitudeDelta * 364_000 * cos(center.latitude * .pi / 180)
    }

    /// Geometric mean of N–S / E–W sides — used for the size slider.
    var approxSideFeet: Double {
        sqrt(max(sideFeetNS, 1) * max(sideFeetEW, 1))
    }

    var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta * 1.15,
                longitudeDelta: longitudeDelta * 1.15
            )
        )
    }

    /// MapKit camera fence for locking project view to this Job Site.
    var mapRect: MKMapRect {
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: west))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: east))
        let minX = min(nw.x, se.x)
        let minY = min(nw.y, se.y)
        let maxX = max(nw.x, se.x)
        let maxY = max(nw.y, se.y)
        return MKMapRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    var cornerCoordinates: [CLLocationCoordinate2D] {
        [
            CLLocationCoordinate2D(latitude: north, longitude: west),
            CLLocationCoordinate2D(latitude: north, longitude: east),
            CLLocationCoordinate2D(latitude: south, longitude: east),
            CLLocationCoordinate2D(latitude: south, longitude: west)
        ]
    }

    var isValid: Bool {
        north > south && east != west
            && abs(north) <= 90 && abs(south) <= 90
            && abs(east) <= 180 && abs(west) <= 180
    }

    static func from(region: MKCoordinateRegion, shrinkFactor: Double = 0.92) -> JobSiteBounds {
        let halfLat = region.span.latitudeDelta * 0.5 * shrinkFactor
        let halfLon = region.span.longitudeDelta * 0.5 * shrinkFactor
        return JobSiteBounds(
            north: region.center.latitude + halfLat,
            south: region.center.latitude - halfLat,
            east: region.center.longitude + halfLon,
            west: region.center.longitude - halfLon
        )
    }

    static func from(
        heightmap: HeightmapResult,
        origin: CLLocationCoordinate2D,
        paddingFactor: Double = 1.1
    ) -> JobSiteBounds {
        let region = ContourMapGeoref.region(
            heightmap: heightmap,
            origin: origin,
            paddingFactor: paddingFactor
        )
        return from(region: region, shrinkFactor: 1.0)
    }

    /// Square Job Site centered on a point (useful default on phone).
    static func square(center: CLLocationCoordinate2D, halfSideMeters: Double) -> JobSiteBounds {
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = max(metersPerDegLat * cos(center.latitude * .pi / 180), 1e-6)
        let dLat = halfSideMeters / metersPerDegLat
        let dLon = halfSideMeters / metersPerDegLon
        return JobSiteBounds(
            north: center.latitude + dLat,
            south: center.latitude - dLat,
            east: center.longitude + dLon,
            west: center.longitude - dLon
        )
    }

    static func square(center: CLLocationCoordinate2D, sideFeet: Double) -> JobSiteBounds {
        square(center: center, halfSideMeters: JobSiteDefaults.halfSideMeters(sideFeet: sideFeet))
    }

    /// Keep center; resize to a square of the given side length in feet.
    func resizedToSideFeet(_ sideFeet: Double) -> JobSiteBounds {
        JobSiteBounds.square(center: center, sideFeet: sideFeet)
    }

    func expanded(meters: Double) -> JobSiteBounds {
        let metersPerDegLat = 111_320.0
        let midLat = (north + south) / 2
        let metersPerDegLon = max(metersPerDegLat * cos(midLat * .pi / 180), 1e-6)
        let dLat = meters / metersPerDegLat
        let dLon = meters / metersPerDegLon
        return JobSiteBounds(
            north: north + dLat,
            south: south - dLat,
            east: east + dLon,
            west: west - dLon
        )
    }
}

enum MapTileMath {
    static func tileX(longitude: Double, zoom: Int) -> Int {
        let n = pow(2.0, Double(zoom))
        var x = Int(floor((longitude + 180.0) / 360.0 * n))
        let maxIndex = Int(n) - 1
        x = min(max(x, 0), maxIndex)
        return x
    }

    static func tileY(latitude: Double, zoom: Int) -> Int {
        let lat = min(max(latitude, -85.05112878), 85.05112878)
        let latRad = lat * .pi / 180.0
        let n = pow(2.0, Double(zoom))
        let y = Int(floor((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n))
        let maxIndex = Int(n) - 1
        return min(max(y, 0), maxIndex)
    }

    static func tilesCovering(bounds: JobSiteBounds, zoom: Int) -> [(x: Int, y: Int)] {
        let minX = tileX(longitude: min(bounds.west, bounds.east), zoom: zoom)
        let maxX = tileX(longitude: max(bounds.west, bounds.east), zoom: zoom)
        let minY = tileY(latitude: max(bounds.north, bounds.south), zoom: zoom)
        let maxY = tileY(latitude: min(bounds.north, bounds.south), zoom: zoom)
        var out: [(Int, Int)] = []
        for x in minX...maxX {
            for y in minY...maxY {
                out.append((x, y))
            }
        }
        return out
    }
}
