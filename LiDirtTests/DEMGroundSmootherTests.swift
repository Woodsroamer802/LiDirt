import XCTest
@testable import LiDirt

final class DEMGroundSmootherTests: XCTestCase {
    func testAsScannedReturnsUnchanged() {
        let dem = makeDEM(base: 10, spikeAt: (1, 1, 0.2))
        let out = DEMGroundSmoother.prepareForContours(dem, mode: .asScanned)
        XCTAssertEqual(out.elevations, dem.elevations)
    }

    func testSmoothedReducesIsolatedSpike() {
        let dem = makeDEM(base: 10, spikeAt: (2, 2, 0.25)) // 25 cm spike on flat pad
        let smoothed = DEMGroundSmoother.prepareForContours(
            dem,
            mode: .smoothedGround,
            radiusM: 0.15, // ~3 cells at 0.05 m
            spikeThresholdM: 0.03
        )
        let spike = smoothed.elevations[2 * dem.width + 2]
        XCTAssertFalse(spike.isNaN)
        XCTAssertEqual(Double(spike), 10, accuracy: 0.05)
    }

    func testSmoothedPreservesBroadRamp() {
        // Gentle ramp should survive foot-scale smoothing.
        var cells = [Float](repeating: 0, count: 25)
        for row in 0..<5 {
            for col in 0..<5 {
                cells[row * 5 + col] = Float(col) * 0.05 // 5 cm per cell east
            }
        }
        let dem = HeightmapResult(
            elevations: cells,
            width: 5,
            height: 5,
            cellSizeM: 0.05,
            originX: 0,
            originZ: 0,
            sampleCounts: [Int](repeating: 4, count: 25),
            filledFlags: [Bool](repeating: false, count: 25),
            bounds: HeightmapBounds(minX: 0, maxX: 0.25, minZ: 0, maxZ: 0.25, minY: 0, maxY: 0.2)
        )
        let smoothed = DEMGroundSmoother.smooth(dem, radiusM: 0.06, spikeThresholdM: 0.2)
        let left = smoothed.elevations[2 * 5 + 0]
        let right = smoothed.elevations[2 * 5 + 4]
        XCTAssertGreaterThan(right, left)
        XCTAssertEqual(Double(right - left), 0.2, accuracy: 0.05)
    }

    private func makeDEM(base: Float, spikeAt: (Int, Int, Float)) -> HeightmapResult {
        let w = 5
        let h = 5
        var elevations = [Float](repeating: base, count: w * h)
        elevations[spikeAt.1 * w + spikeAt.0] = base + spikeAt.2
        return HeightmapResult(
            elevations: elevations,
            width: w,
            height: h,
            cellSizeM: 0.05,
            originX: 0,
            originZ: 0,
            sampleCounts: [Int](repeating: 4, count: w * h),
            filledFlags: [Bool](repeating: false, count: w * h),
            bounds: HeightmapBounds(
                minX: 0, maxX: Double(w) * 0.05,
                minZ: 0, maxZ: Double(h) * 0.05,
                minY: Double(base), maxY: Double(base + spikeAt.2)
            )
        )
    }
}
