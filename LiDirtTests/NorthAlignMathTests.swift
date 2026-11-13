import XCTest
import simd
@testable import LiDirt

final class NorthAlignMathTests: XCTestCase {
    func testRotateAroundYPreservesYAndLength() {
        let p = SIMD3<Float>(3, 1.5, 4)
        let rotated = NorthAlignMath.rotateAroundY(p, yawRadians: .pi / 2)
        XCTAssertEqual(rotated.y, 1.5, accuracy: 1e-5)
        XCTAssertEqual(simd_length(rotated), simd_length(p), accuracy: 1e-5)
    }

    func testNorthAlignYawIdentityWhenFacingNorth() {
        // Device forward along +Z, compass heading 0 (north) → yaw aligns forward to +Z.
        let yaw = NorthAlignMath.northAlignYaw(arkitForwardYawRadians: 0, compassHeadingDegrees: 0)
        XCTAssertEqual(yaw, 0, accuracy: 1e-9)
    }

    func testMetadataIncludesHeadingWhenOriented() throws {
        var cells: [DEMGridKey: DEMCellStats] = [:]
        for iz in 0..<2 {
            for ix in 0..<2 {
                var s = DEMCellStats()
                for _ in 0..<4 { s.addSample(0.5) }
                cells[DEMGridKey(ix: ix, iz: iz)] = s
            }
        }
        let heightmap = DEMBuilder.buildHeightmap(cells: cells, cellSizeM: 0.05)!
        let metrics = QualityScorer.score(cells: cells, heightmap: heightmap, passCount: 2)
        let orientation = ScanOrientationSnapshot(
            method: "phone_compass_gps",
            latitude: 30.0,
            longitude: -97.0,
            horizontalAccuracyM: 8,
            headingDegrees: 12,
            headingAccuracyDegrees: 5,
            headingSource: "trueHeading",
            northAlignYawRadians: 0.2,
            frameAlignedToNorth: true,
            disclaimer: ScanOrientationSnapshot.phoneDisclaimer
        )
        let metadata = ScanPackageWriter.makeMetadata(
            scanId: UUID(),
            projectId: UUID(),
            heightmap: heightmap,
            metrics: metrics,
            durationSec: 10,
            minSamplesPerCell: 3,
            preferredContourIntervalInches: 0.125,
            controlPointsCount: 0,
            hasLiDAR: true,
            orientation: orientation
        )
        XCTAssertTrue(metadata.frame.alignedToNorth)
        XCTAssertEqual(metadata.georef.method, "phone_compass_gps")
        XCTAssertEqual(metadata.georef.heading.source, "trueHeading")
        XCTAssertEqual(metadata.frame.rowDirection, "+North (+Z)")
        let data = try ScanPackageWriter.encodeMetadata(metadata)
        let decoded = try ScanPackageWriter.decodeMetadata(from: data)
        XCTAssertEqual(decoded.georef.heading.degrees, 12)
        XCTAssertTrue(decoded.georef.heading.disclaimer.contains("Not survey-grade"))
    }
}
