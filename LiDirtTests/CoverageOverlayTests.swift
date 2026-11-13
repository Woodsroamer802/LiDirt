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
}
