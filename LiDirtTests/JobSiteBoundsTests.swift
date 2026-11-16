import XCTest
import CoreLocation
import MapKit
@testable import LiDirt

final class JobSiteBoundsTests: XCTestCase {
    func testFromRegionProducesValidBounds() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 44.5, longitude: -73.2),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.02)
        )
        let bounds = JobSiteBounds.from(region: region)
        XCTAssertTrue(bounds.isValid)
        XCTAssertGreaterThan(bounds.north, bounds.south)
        XCTAssertEqual(bounds.center.latitude, 44.5, accuracy: 1e-6)
    }

    func testSquareCentered() {
        let center = CLLocationCoordinate2D(latitude: 40, longitude: -100)
        let bounds = JobSiteBounds.square(center: center, halfSideMeters: 50)
        XCTAssertTrue(bounds.isValid)
        XCTAssertEqual(bounds.center.latitude, 40, accuracy: 1e-5)
        XCTAssertEqual(bounds.center.longitude, -100, accuracy: 1e-5)
        XCTAssertEqual(bounds.cornerCoordinates.count, 4)
    }

    func testSideFeetResizeKeepsCenter() {
        let center = CLLocationCoordinate2D(latitude: 44.0, longitude: -73.0)
        let small = JobSiteBounds.square(center: center, sideFeet: 10) // ~100 sq ft
        XCTAssertTrue(small.isValid)
        XCTAssertEqual(small.approxSideFeet, 10, accuracy: 0.5)
        let resized = small.resizedToSideFeet(100)
        XCTAssertEqual(resized.center.latitude, center.latitude, accuracy: 1e-6)
        XCTAssertEqual(resized.approxSideFeet, 100, accuracy: 2)
        XCTAssertFalse(resized.mapRect.isNull)
    }

    func testDefaultsClamp() {
        XCTAssertEqual(JobSiteDefaults.clampSideFeet(1), JobSiteDefaults.minSideFeet)
        XCTAssertEqual(JobSiteDefaults.clampSideFeet(5000), JobSiteDefaults.maxSideFeet)
        XCTAssertEqual(JobSiteDefaults.halfSideMeters(sideFeet: 100), 100 * 0.3048 / 2, accuracy: 1e-9)
    }

    func testRectangleWidthLengthAndNudge() {
        let center = CLLocationCoordinate2D(latitude: 44.0, longitude: -73.0)
        let rect = JobSiteBounds.rectangle(center: center, widthFeet: 20, lengthFeet: 40)
        XCTAssertTrue(rect.isValid)
        XCTAssertEqual(rect.widthFeet, 20, accuracy: 0.01)
        XCTAssertEqual(rect.lengthFeet, 40, accuracy: 0.01)
        XCTAssertEqual(rect.sideFeetEW, 20, accuracy: 1)
        XCTAssertEqual(rect.sideFeetNS, 40, accuracy: 1)
        let moved = rect.nudged(eastFeet: 10, northFeet: -5)
        XCTAssertGreaterThan(moved.center.longitude, rect.center.longitude)
        XCTAssertLessThan(moved.center.latitude, rect.center.latitude)
        XCTAssertEqual(moved.widthFeet, rect.widthFeet, accuracy: 0.01)
        let recentered = rect.recentered(to: CLLocationCoordinate2D(latitude: 44.01, longitude: -73.01))
        XCTAssertEqual(recentered.center.latitude, 44.01, accuracy: 1e-6)
        XCTAssertEqual(recentered.lengthFeet, 40, accuracy: 0.01)
    }

    func testRotationPreservesSizeAndGrowsAABB() {
        let center = CLLocationCoordinate2D(latitude: 44.0, longitude: -73.0)
        let rect = JobSiteBounds.rectangle(center: center, widthFeet: 20, lengthFeet: 40)
        let rotated = rect.withRotationDegrees(45)
        XCTAssertEqual(rotated.widthFeet, 20, accuracy: 0.01)
        XCTAssertEqual(rotated.lengthFeet, 40, accuracy: 0.01)
        XCTAssertEqual(rotated.rotationDegrees, 45, accuracy: 0.01)
        XCTAssertEqual(rotated.cornerCoordinates.count, 4)
        // Axis-aligned footprint must grow when the rectangle is diamond-oriented.
        XCTAssertGreaterThan(rotated.sideFeetEW, rect.sideFeetEW + 5)
        XCTAssertGreaterThan(rotated.sideFeetNS, rect.sideFeetNS - 1)
        let roundTrip = try! JSONDecoder().decode(
            JobSiteBounds.self,
            from: JSONEncoder().encode(rotated)
        )
        XCTAssertEqual(roundTrip.rotationDegrees, 45, accuracy: 0.01)
        XCTAssertEqual(roundTrip.widthFeet, 20, accuracy: 0.5)
    }

    func testAdaptiveFusedRenderLongEdge() {
        let center = CLLocationCoordinate2D(latitude: 40, longitude: -100)
        let small = JobSiteBounds.square(center: center, sideFeet: 12)
        let edge = FusedSiteMapRenderer.longEdgePixels(for: small)
        XCTAssertGreaterThanOrEqual(edge, FusedSiteMapRenderer.minLongEdgePixels)
        XCTAssertLessThanOrEqual(edge, FusedSiteMapRenderer.maxLongEdgePixels)
    }

    func testTileMathCoversBounds() {
        let bounds = JobSiteBounds(north: 44.51, south: 44.50, east: -73.19, west: -73.20)
        let tiles = MapTileMath.tilesCovering(bounds: bounds, zoom: 14)
        XCTAssertFalse(tiles.isEmpty)
        XCTAssertLessThan(tiles.count, 20)
    }

    func testSnapshotAspectLandscape() {
        let bounds = JobSiteBounds(north: 1, south: 0, east: 2, west: 0) // wider
        let size = JobSiteOfflineStore.snapshotPixelSize(for: bounds)
        XCTAssertEqual(size.width, JobSiteOfflineStore.longEdgePixels)
        XCTAssertLessThan(size.height, size.width)
    }
}

