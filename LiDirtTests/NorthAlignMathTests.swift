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

    func testNorthAlignYawFacingEastLeavesSessionWhenAlreadyENU() {
        // Session already ENU (+Z north): facing east → arYaw = +π/2, compass = 90°.
        let yaw = NorthAlignMath.northAlignYaw(
            arkitForwardYawRadians: .pi / 2,
            compassHeadingDegrees: 90
        )
        XCTAssertEqual(yaw, 0, accuracy: 1e-9)
    }

    func testNorthAlignCorrectsWhenSessionZIsEast() {
        // Session +Z points east; user faces north (compass 0). Camera forward is −X
        // in that frame → arYaw = atan2(-1, 0) = −π/2. Need +90° rotation so +Z → north.
        let yaw = NorthAlignMath.northAlignYaw(
            arkitForwardYawRadians: -.pi / 2,
            compassHeadingDegrees: 0
        )
        XCTAssertEqual(yaw, -.pi / 2, accuracy: 1e-9)
        let northInSession = SIMD3<Float>(-1, 0, 0) // north when +Z was east
        let aligned = NorthAlignMath.rotateAroundY(northInSession, yawRadians: yaw)
        XCTAssertEqual(aligned.x, 0, accuracy: 1e-5)
        XCTAssertEqual(aligned.z, 1, accuracy: 1e-5) // +Z north
    }

    func testNorthAlignMapsDeviceForwardToCompassBearing() {
        // Arbitrary session: device forward at 30°, compass says 75° → rotate so forward → 75° ENU.
        let arYaw = 30.0 * .pi / 180.0
        let compass = 75.0
        let yaw = NorthAlignMath.northAlignYaw(
            arkitForwardYawRadians: arYaw,
            compassHeadingDegrees: compass
        )
        let forward = SIMD3<Float>(Float(sin(arYaw)), 0, Float(cos(arYaw)))
        let aligned = NorthAlignMath.rotateAroundY(forward, yawRadians: yaw)
        let enu = NorthAlignMath.enuYaw(xEast: aligned.x, zNorth: aligned.z)
        XCTAssertEqual(enu, compass * .pi / 180.0, accuracy: 1e-5)
    }

    func testOldPlusFormulaWouldMirrorHeading() {
        // Document why `+` was wrong: facing 22.5° would leave a ~45° error and reverse sense.
        let arYaw = 0.0
        let compass = 22.5
        let correct = NorthAlignMath.northAlignYaw(
            arkitForwardYawRadians: arYaw,
            compassHeadingDegrees: compass
        )
        let wrongPlus = arYaw + compass * .pi / 180.0
        XCTAssertEqual(abs(wrongPlus - correct), 2 * compass * .pi / 180.0, accuracy: 1e-9)
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
            disclaimer: ScanOrientationSnapshot.phoneDisclaimer,
            northAlignConvention: NorthAlignMath.conventionENUSubtract
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
