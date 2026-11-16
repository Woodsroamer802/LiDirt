import Foundation
import CoreLocation
import MapKit

/// Shared Job Site outline / download size defaults (feet).
enum JobSiteDefaults {
    /// ~10 ft — supports ~100 sq ft pads when square.
    static let minSideFeet: Double = 10
    static let maxSideFeet: Double = 1_000
    /// Sensible starting outline; user can shrink before download.
    static let defaultSideFeet: Double = 100
    /// Nudge step when repositioning the Job Site border.
    static let nudgeFeet: Double = 10

    static func clampSideFeet(_ feet: Double) -> Double {
        min(max(feet, minSideFeet), maxSideFeet)
    }

    static func halfSideMeters(sideFeet: Double) -> Double {
        (clampSideFeet(sideFeet) * 0.3048) / 2.0
    }
}

/// Geographic Job Site outline — rectangle that can be **rotated**.
/// `north/south/east/west` always store the axis-aligned bounding box (camera / render).
/// `widthFeet` / `lengthFeet` / `rotationDegrees` define the oriented crop frame.
struct JobSiteBounds: Codable, Equatable, Sendable, Hashable {
    var north: Double
    var south: Double
    var east: Double
    var west: Double
    /// Oriented width in feet (east axis before rotation).
    var widthFeet: Double
    /// Oriented length in feet (north axis before rotation).
    var lengthFeet: Double
    /// Degrees clockwise from north. 0 = sides parallel to lat/lon.
    var rotationDegrees: Double

    enum CodingKeys: String, CodingKey {
        case north, south, east, west, widthFeet, lengthFeet, rotationDegrees
    }

    init(
        north: Double,
        south: Double,
        east: Double,
        west: Double,
        widthFeet: Double? = nil,
        lengthFeet: Double? = nil,
        rotationDegrees: Double = 0
    ) {
        self.north = north
        self.south = south
        self.east = east
        self.west = west
        let center = CLLocationCoordinate2D(
            latitude: (north + south) / 2,
            longitude: (east + west) / 2
        )
        let aabbW = max(east - west, 1e-9) * 364_000 * cos(center.latitude * .pi / 180)
        let aabbL = max(north - south, 1e-9) * 364_000
        self.widthFeet = JobSiteDefaults.clampSideFeet(widthFeet ?? aabbW)
        self.lengthFeet = JobSiteDefaults.clampSideFeet(lengthFeet ?? aabbL)
        self.rotationDegrees = rotationDegrees.truncatingRemainder(dividingBy: 360)
        recomputeAABB()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        north = try c.decode(Double.self, forKey: .north)
        south = try c.decode(Double.self, forKey: .south)
        east = try c.decode(Double.self, forKey: .east)
        west = try c.decode(Double.self, forKey: .west)
        let center = CLLocationCoordinate2D(
            latitude: (north + south) / 2,
            longitude: (east + west) / 2
        )
        let aabbW = max(east - west, 1e-9) * 364_000 * cos(center.latitude * .pi / 180)
        let aabbL = max(north - south, 1e-9) * 364_000
        widthFeet = JobSiteDefaults.clampSideFeet(
            try c.decodeIfPresent(Double.self, forKey: .widthFeet) ?? aabbW
        )
        lengthFeet = JobSiteDefaults.clampSideFeet(
            try c.decodeIfPresent(Double.self, forKey: .lengthFeet) ?? aabbL
        )
        rotationDegrees = try c.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        recomputeAABB()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(north, forKey: .north)
        try c.encode(south, forKey: .south)
        try c.encode(east, forKey: .east)
        try c.encode(west, forKey: .west)
        try c.encode(widthFeet, forKey: .widthFeet)
        try c.encode(lengthFeet, forKey: .lengthFeet)
        try c.encode(rotationDegrees, forKey: .rotationDegrees)
    }

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (north + south) / 2,
            longitude: (east + west) / 2
        )
    }

    var latitudeDelta: Double { max(north - south, 1e-6) }
    var longitudeDelta: Double { max(east - west, 1e-6) }

    /// AABB north–south extent in feet (grows when rotated).
    var sideFeetNS: Double { latitudeDelta * 364_000 }

    /// AABB east–west extent in feet (grows when rotated).
    var sideFeetEW: Double {
        longitudeDelta * 364_000 * cos(center.latitude * .pi / 180)
    }

    var approxSideFeet: Double {
        sqrt(max(widthFeet, 1) * max(lengthFeet, 1))
    }

    var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta * 1.2,
                longitudeDelta: longitudeDelta * 1.2
            )
        )
    }

    /// MapKit camera fence for locking project view to this Job Site (AABB).
    var mapRect: MKMapRect {
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: west))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: east))
        let minX = min(nw.x, se.x)
        let minY = min(nw.y, se.y)
        let maxX = max(nw.x, se.x)
        let maxY = max(nw.y, se.y)
        return MKMapRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    /// Oriented rectangle corners (NW→NE→SE→SW in local frame before rotation).
    var cornerCoordinates: [CLLocationCoordinate2D] {
        orientedCorners()
    }

    var isValid: Bool {
        north > south && east != west
            && abs(north) <= 90 && abs(south) <= 90
            && abs(east) <= 180 && abs(west) <= 180
            && widthFeet >= JobSiteDefaults.minSideFeet * 0.5
            && lengthFeet >= JobSiteDefaults.minSideFeet * 0.5
    }

    static func from(region: MKCoordinateRegion, shrinkFactor: Double = 0.92) -> JobSiteBounds {
        let halfLat = region.span.latitudeDelta * 0.5 * shrinkFactor
        let halfLon = region.span.longitudeDelta * 0.5 * shrinkFactor
        return JobSiteBounds(
            north: region.center.latitude + halfLat,
            south: region.center.latitude - halfLat,
            east: region.center.longitude + halfLon,
            west: region.center.longitude - halfLon,
            rotationDegrees: 0
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

    static func square(center: CLLocationCoordinate2D, halfSideMeters: Double) -> JobSiteBounds {
        let sideFeet = (halfSideMeters * 2) / 0.3048
        return rectangle(center: center, widthFeet: sideFeet, lengthFeet: sideFeet, rotationDegrees: 0)
    }

    static func square(center: CLLocationCoordinate2D, sideFeet: Double) -> JobSiteBounds {
        rectangle(center: center, widthFeet: sideFeet, lengthFeet: sideFeet, rotationDegrees: 0)
    }

    /// Oriented rectangle. `widthFeet` = local east axis, `lengthFeet` = local north axis before rotation.
    static func rectangle(
        center: CLLocationCoordinate2D,
        widthFeet: Double,
        lengthFeet: Double,
        rotationDegrees: Double = 0
    ) -> JobSiteBounds {
        var bounds = JobSiteBounds(
            north: center.latitude,
            south: center.latitude,
            east: center.longitude,
            west: center.longitude,
            widthFeet: widthFeet,
            lengthFeet: lengthFeet,
            rotationDegrees: rotationDegrees
        )
        // Seed a tiny AABB around center, then size via recompute.
        bounds.north = center.latitude + 1e-6
        bounds.south = center.latitude - 1e-6
        bounds.east = center.longitude + 1e-6
        bounds.west = center.longitude - 1e-6
        bounds.widthFeet = JobSiteDefaults.clampSideFeet(widthFeet)
        bounds.lengthFeet = JobSiteDefaults.clampSideFeet(lengthFeet)
        bounds.rotationDegrees = rotationDegrees.truncatingRemainder(dividingBy: 360)
        bounds.recomputeAABB()
        return bounds
    }

    func resizedToSideFeet(_ sideFeet: Double) -> JobSiteBounds {
        JobSiteBounds.rectangle(
            center: center,
            widthFeet: sideFeet,
            lengthFeet: sideFeet,
            rotationDegrees: rotationDegrees
        )
    }

    func resizedToFeet(widthFeet: Double, lengthFeet: Double) -> JobSiteBounds {
        JobSiteBounds.rectangle(
            center: center,
            widthFeet: widthFeet,
            lengthFeet: lengthFeet,
            rotationDegrees: rotationDegrees
        )
    }

    func rotated(byDegrees delta: Double) -> JobSiteBounds {
        JobSiteBounds.rectangle(
            center: center,
            widthFeet: widthFeet,
            lengthFeet: lengthFeet,
            rotationDegrees: rotationDegrees + delta
        )
    }

    func withRotationDegrees(_ degrees: Double) -> JobSiteBounds {
        JobSiteBounds.rectangle(
            center: center,
            widthFeet: widthFeet,
            lengthFeet: lengthFeet,
            rotationDegrees: degrees
        )
    }

    func nudged(eastFeet: Double, northFeet: Double) -> JobSiteBounds {
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = max(metersPerDegLat * cos(center.latitude * .pi / 180), 1e-6)
        let dLat = (northFeet * 0.3048) / metersPerDegLat
        let dLon = (eastFeet * 0.3048) / metersPerDegLon
        let newCenter = CLLocationCoordinate2D(
            latitude: center.latitude + dLat,
            longitude: center.longitude + dLon
        )
        return recentered(to: newCenter)
    }

    func recentered(to newCenter: CLLocationCoordinate2D) -> JobSiteBounds {
        JobSiteBounds.rectangle(
            center: newCenter,
            widthFeet: widthFeet,
            lengthFeet: lengthFeet,
            rotationDegrees: rotationDegrees
        )
    }

    func expanded(meters: Double) -> JobSiteBounds {
        let extraFeet = meters / 0.3048
        return resizedToFeet(
            widthFeet: widthFeet + extraFeet * 2,
            lengthFeet: lengthFeet + extraFeet * 2
        )
    }

    /// Rebuild N/S/E/W from oriented corners so camera lock / fused render cover the crop.
    mutating func recomputeAABB() {
        let corners = orientedCorners()
        guard let maxLat = corners.map(\.latitude).max(),
              let minLat = corners.map(\.latitude).min(),
              let maxLon = corners.map(\.longitude).max(),
              let minLon = corners.map(\.longitude).min() else { return }
        north = maxLat
        south = minLat
        east = maxLon
        west = minLon
    }

    private func orientedCorners() -> [CLLocationCoordinate2D] {
        let c = center
        let halfW = JobSiteDefaults.halfSideMeters(sideFeet: widthFeet)
        let halfL = JobSiteDefaults.halfSideMeters(sideFeet: lengthFeet)
        let θ = rotationDegrees * .pi / 180
        let cosθ = cos(θ)
        let sinθ = sin(θ)
        // Local east/north offsets before rotation (NW, NE, SE, SW).
        let locals: [(Double, Double)] = [
            (-halfW, halfL),
            (halfW, halfL),
            (halfW, -halfL),
            (-halfW, -halfL)
        ]
        return locals.map { eastM, northM in
            // Clockwise from north: east' = e·cos + n·sin, north' = -e·sin + n·cos
            let ee = eastM * cosθ + northM * sinθ
            let nn = -eastM * sinθ + northM * cosθ
            return ContourMapGeoref.coordinate(
                localXMetersEast: ee,
                localZMetersNorth: nn,
                origin: c
            )
        }
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
