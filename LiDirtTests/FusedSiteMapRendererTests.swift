import XCTest
import CoreLocation
@testable import LiDirt

final class FusedSiteMapRendererTests: XCTestCase {
    func testRendersHillshadeForSmallJobSite() throws {
        var cells: [DEMGridKey: DEMCellStats] = [:]
        for iz in 0..<8 {
            for ix in 0..<8 {
                var stats = DEMCellStats()
                let elev = Double(ix + iz) * 0.02
                for _ in 0..<5 { stats.addSample(elev) }
                cells[DEMGridKey(ix: ix, iz: iz)] = stats
            }
        }
        let heightmap = try XCTUnwrap(
            DEMBuilder.buildHeightmap(cells: cells, cellSizeM: 0.5, minSamples: 3, fillOneCellGaps: false)
        )
        let origin = CLLocationCoordinate2D(latitude: 44.0, longitude: -73.0)
        // ~12×12 ft ≈ 144 sq ft
        let bounds = JobSiteBounds.square(center: origin, sideFeet: 12)
        let rendered = try XCTUnwrap(
            FusedSiteMapRenderer.render(
                heightmap: heightmap,
                origin: origin,
                bounds: bounds,
                intervalInches: 1,
                drawContours: true,
                longEdge: 256
            )
        )
        XCTAssertGreaterThan(rendered.pixelWidth, 32)
        XCTAssertGreaterThan(rendered.pixelHeight, 32)
        XCTAssertEqual(rendered.bounds.approxSideFeet, 12, accuracy: 1)
        XCTAssertFalse(rendered.pngData.isEmpty)
        XCTAssertNotNil(rendered.image)
    }

    func testLocalMetersRoundTrip() {
        let origin = CLLocationCoordinate2D(latitude: 40, longitude: -100)
        let coord = ContourMapGeoref.coordinate(
            localXMetersEast: 25,
            localZMetersNorth: -10,
            origin: origin
        )
        let local = ContourMapGeoref.localMeters(coordinate: coord, origin: origin)
        XCTAssertEqual(local.x, 25, accuracy: 1e-4)
        XCTAssertEqual(local.z, -10, accuracy: 1e-4)
    }
}
