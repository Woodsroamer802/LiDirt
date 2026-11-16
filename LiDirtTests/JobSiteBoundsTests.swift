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

