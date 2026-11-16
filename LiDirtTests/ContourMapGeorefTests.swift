import XCTest
import CoreLocation
@testable import LiDirt

final class ContourMapGeorefTests: XCTestCase {
    func testCoordinateOffsetsEastAndNorth() {
        let origin = CLLocationCoordinate2D(latitude: 44.0, longitude: -73.0)
        let east = ContourMapGeoref.coordinate(
            localXMetersEast: 111.32,
            localZMetersNorth: 0,
            origin: origin
        )
        let north = ContourMapGeoref.coordinate(
            localXMetersEast: 0,
            localZMetersNorth: 111.32,
            origin: origin
        )
        XCTAssertGreaterThan(east.longitude, origin.longitude)
        XCTAssertEqual(east.latitude, origin.latitude, accuracy: 1e-8)
        XCTAssertGreaterThan(north.latitude, origin.latitude)
        XCTAssertEqual(north.longitude, origin.longitude, accuracy: 1e-8)
    }

    func testLocalSegmentsProduceDistinctEndpoints() throws {
        var cells: [DEMGridKey: DEMCellStats] = [:]
        // 3x3 ramp so several contour levels cross cell edges.
        for iz in 0..<3 {
            for ix in 0..<3 {
                var stats = DEMCellStats()
                let elev = Double(ix + iz) * 0.05 // meters (~2 in steps)
                for _ in 0..<5 { stats.addSample(elev) }
                cells[DEMGridKey(ix: ix, iz: iz)] = stats
            }
        }
        let heightmap = try XCTUnwrap(DEMBuilder.buildHeightmap(cells: cells, cellSizeM: 0.05, minSamples: 3, fillOneCellGaps: false))
        let segs = ContourPreview.localSegments(heightmap: heightmap, intervalM: 0.0254) // 1 inch
        XCTAssertFalse(segs.isEmpty)
        for seg in segs {
            let dx = seg.ax - seg.bx
            let dz = seg.az - seg.bz
            XCTAssertGreaterThan(dx * dx + dz * dz, 1e-12, "segment should be a line, not a point")
        }
    }

    func testPolylinesRequirePositiveInterval() throws {
        var cells: [DEMGridKey: DEMCellStats] = [:]
        for iz in 0..<2 {
            for ix in 0..<2 {
                var stats = DEMCellStats()
                for _ in 0..<4 { stats.addSample(Double(ix) * 0.1) }
                cells[DEMGridKey(ix: ix, iz: iz)] = stats
            }
        }
        let heightmap = try XCTUnwrap(DEMBuilder.buildHeightmap(cells: cells, cellSizeM: 0.05, minSamples: 3, fillOneCellGaps: false))
        let origin = CLLocationCoordinate2D(latitude: 40, longitude: -100)
        let lines = ContourMapGeoref.polylines(heightmap: heightmap, origin: origin, intervalInches: 1)
        XCTAssertFalse(lines.isEmpty)
        XCTAssertEqual(lines[0].coordinates.count, 2)
    }
}
