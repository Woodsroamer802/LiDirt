import XCTest
@testable import LiDirt

final class DEMBuilderTests: XCTestCase {
    func testMultiPassAveragingIncreasesCountAndAveragesElevation() {
        let acc = DEMAccumulator(cellSizeM: 0.05)
        // First pass
        for _ in 0..<3 {
            acc.addSample(x: 1.02, y: 1.0, z: 2.01)
        }
        // Second pass same cell, higher readings
        for _ in 0..<3 {
            acc.addSample(x: 1.03, y: 1.2, z: 2.02)
        }

        let cells = acc.snapshot()
        let key = DEMGridKey(ix: Int(floor(1.02 / 0.05)), iz: Int(floor(2.01 / 0.05)))
        XCTAssertEqual(cells[key]?.count, 6)
        XCTAssertEqual(cells[key]?.mean ?? -1, 1.1, accuracy: 1e-9)

        let heightmap = DEMBuilder.buildHeightmap(cells: cells, cellSizeM: 0.05, minSamples: 3, fillOneCellGaps: false)
        XCTAssertNotNil(heightmap)
        XCTAssertEqual(heightmap?.sampleCounts.first { $0 > 0 }, 6)
        let elev = heightmap?.elevations.first { !$0.isNaN }
        XCTAssertEqual(Double(elev ?? -1), 1.1, accuracy: 1e-5)
    }

    func testHolesAreNaNBelowMinSamples() {
        var cells: [DEMGridKey: DEMCellStats] = [:]
        var good = DEMCellStats()
        for _ in 0..<3 { good.addSample(0.5) }
        cells[DEMGridKey(ix: 0, iz: 0)] = good

        var thin = DEMCellStats()
        thin.addSample(0.4)
        thin.addSample(0.6)
        cells[DEMGridKey(ix: 1, iz: 0)] = thin

        let heightmap = DEMBuilder.buildHeightmap(cells: cells, cellSizeM: 0.05, minSamples: 3, fillOneCellGaps: false)!
        // Bounding box includes thin cell as hole
        XCTAssertEqual(heightmap.width, 2)
        XCTAssertFalse(heightmap.elevations[0].isNaN)
        XCTAssertTrue(heightmap.elevations[1].isNaN)
    }

    func testSingleCellGapFillMarksFilledFlag() {
        var cells: [DEMGridKey: DEMCellStats] = [:]
        func fill(_ ix: Int, _ iz: Int, _ y: Double) {
            var s = DEMCellStats()
            for _ in 0..<3 { s.addSample(y) }
            cells[DEMGridKey(ix: ix, iz: iz)] = s
        }
        // 3x3 with center missing
        for iz in 0..<3 {
            for ix in 0..<3 {
                if ix == 1 && iz == 1 { continue }
                fill(ix, iz, 2.0)
            }
        }

        let heightmap = DEMBuilder.buildHeightmap(cells: cells, cellSizeM: 0.05, minSamples: 3, fillOneCellGaps: true)!
        let center = 1 * heightmap.width + 1
        XCTAssertFalse(heightmap.elevations[center].isNaN)
        XCTAssertTrue(heightmap.filledFlags[center])
    }

    func testEmptyGridReturnsNil() {
        XCTAssertNil(DEMBuilder.buildHeightmap(cells: [:], cellSizeM: 0.05))
    }
}
