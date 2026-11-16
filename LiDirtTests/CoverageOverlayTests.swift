import XCTest
@testable import LiDirt

final class CoverageOverlayTests: XCTestCase {
    func testGreenOnlyWhenGoalMet() {
        XCTAssertEqual(CoverageOverlay.level(sampleCount: 0), .missing)
        XCTAssertEqual(CoverageOverlay.level(sampleCount: 1), .incomplete)
        XCTAssertEqual(CoverageOverlay.level(sampleCount: CoverageGoals.minSamplesForDEM), .incomplete)
        XCTAssertEqual(
            CoverageOverlay.level(sampleCount: CoverageGoals.samplesForGoalMet - 1),
            .incomplete
        )
        XCTAssertEqual(
            CoverageOverlay.level(sampleCount: CoverageGoals.samplesForGoalMet),
            .goalMet
        )
        XCTAssertEqual(
            CoverageOverlay.level(sampleCount: CoverageGoals.samplesForGoalMet + 4),
            .goalMet
        )
    }

    @MainActor
    func testGoalMetPercentUsesWalkedCellsNotEmptyHull() {
        let pipeline = CapturePipeline(cellSizeM: 0.05)
        pipeline.prepareSession()
        pipeline.forceStartSamplingForTests()

        // One cell short of goal, one at goal — walked denominator is 2 → 50%.
        var short: [SIMD3<Float>] = []
        var goal: [SIMD3<Float>] = []
        for _ in 0..<(CoverageGoals.samplesForGoalMet - 1) {
            short.append(SIMD3<Float>(0.01, 0, 0.01))
        }
        for _ in 0..<CoverageGoals.samplesForGoalMet {
            goal.append(SIMD3<Float>(0.20, 0, 0.20))
        }
        pipeline.ingestTestPoints(short)
        pipeline.ingestTestPoints(goal)

        XCTAssertEqual(pipeline.goalMetPercent, 50, accuracy: 0.1)
        XCTAssertGreaterThan(pipeline.trackedAreaM2, 0)
    }
}
