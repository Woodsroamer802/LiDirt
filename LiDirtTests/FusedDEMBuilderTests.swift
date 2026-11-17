import XCTest
@testable import LiDirt

final class FusedDEMBuilderTests: XCTestCase {
    func testVerticalBiasMatchesFoundationMinusLidar() {
        let foundation = makeRampDEM(base: 100, step: 0)
        let lidar = makeRampDEM(base: 2, step: 0)
        let bias = FusedDEMBuilder.verticalBias(foundation: foundation, lidar: lidar)
        XCTAssertEqual(bias, 98, accuracy: 1e-6)
    }

    func testFusePrefersLidarInsideFootprint() {
        let foundation = makeRampDEM(base: 50, step: 0, width: 6, height: 6, cell: 1)
        // Smaller LiDAR island in the middle with relative elev ~1 → bias ~49
        let lidar = makeRampDEM(base: 1, step: 0, width: 2, height: 2, cell: 1, originX: 2, originZ: 2)
        let fused = FusedDEMBuilder.fuse(foundation: foundation, lidar: lidar, featherMeters: 0.1)
        XCTAssertEqual(fused.method, "usgs_3dep_plus_lidar")
        XCTAssertGreaterThan(fused.lidarSampleCount, 0)
        XCTAssertGreaterThan(fused.foundationSampleCount, 0)

        // Center of LiDAR island should be near foundation absolute (~50), not relative 1.
        let mid = FusedDEMBuilder.sampleNearest(fused.heightmap, x: 2.5, z: 2.5)
        XCTAssertNotNil(mid)
        XCTAssertEqual(mid!, 50, accuracy: 0.5)
    }

    func testDecodeUSGSSamples() throws {
        let json = """
        {"samples":[
          {"locationId":0,"value":"12.5"},
          {"locationId":1,"value":13.25}
        ]}
        """
        let values = try USGSElevationService.decodeSamples(Data(json.utf8), expectedCount: 2)
        XCTAssertEqual(values[0], 12.5)
        XCTAssertEqual(values[1], 13.25)
    }

    func testPrintSheetSizes() {
        XCTAssertEqual(PrintSheetSize.archD24x36.widthInches, 36)
        XCTAssertEqual(PrintSheetSize.archD24x36.heightInches, 24)
        XCTAssertEqual(PrintSheetSize.tabloid11x17.widthInches, 17)
        XCTAssertEqual(PrintSheetSize.tabloid11x17.heightInches, 11)
        XCTAssertEqual(PrintSheetSize.archB12x18.widthInches, 18)
        XCTAssertEqual(PrintSheetSize.archB12x18.heightInches, 12)
        XCTAssertEqual(PrintSheetSize.archD24x36.sizePoints.width, 36 * 72)
    }

    private func makeRampDEM(
        base: Double,
        step: Double,
        width: Int = 3,
        height: Int = 3,
        cell: Double = 1,
        originX: Double = 0,
        originZ: Double = 0
    ) -> HeightmapResult {
        var elevations = [Float](repeating: .nan, count: width * height)
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for row in 0..<height {
            for col in 0..<width {
                let elev = base + step * Double(col + row)
                elevations[row * width + col] = Float(elev)
                minY = min(minY, elev)
                maxY = max(maxY, elev)
            }
        }
        return HeightmapResult(
            elevations: elevations,
            width: width,
            height: height,
            cellSizeM: cell,
            originX: originX,
            originZ: originZ,
            sampleCounts: [Int](repeating: 4, count: width * height),
            filledFlags: [Bool](repeating: false, count: width * height),
            bounds: HeightmapBounds(
                minX: originX,
                maxX: originX + Double(width) * cell,
                minZ: originZ,
                maxZ: originZ + Double(height) * cell,
                minY: minY,
                maxY: maxY
            )
        )
    }
}
