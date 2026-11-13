import XCTest
@testable import LiDirt

final class QualityScorerTests: XCTestCase {
    func testScoreBreakpoints() {
        // Ideal: no holes, low RMS, high samples, 2+ passes
        let ideal = QualityScorer.computeScore(
            holeRatio: 0,
            rmsResidualM: 0,
            meanSampleCount: 8,
            passCount: 2
        )
        XCTAssertEqual(ideal, 100)

        // High holes
        let holes = QualityScorer.computeScore(
            holeRatio: 1,
            rmsResidualM: 0,
            meanSampleCount: 8,
            passCount: 2
        )
        XCTAssertEqual(holes, 60)

        // Single pass penalty
        let onePass = QualityScorer.computeScore(
            holeRatio: 0,
            rmsResidualM: 0,
            meanSampleCount: 8,
            passCount: 1
        )
        XCTAssertEqual(onePass, 90)

        // Full RMS penalty at 5 cm
        let rms = QualityScorer.computeScore(
            holeRatio: 0,
            rmsResidualM: 0.05,
            meanSampleCount: 8,
            passCount: 2
        )
        XCTAssertEqual(rms, 70)
    }

    func testLabels() {
        let good = QualityMetrics(
            coverageRatio: 0.95, meanSampleCount: 8, rmsResidualM: 0.01,
            holeRatio: 0.05, passCount: 2, qualityScore: 92
        )
        XCTAssertEqual(good.label, "Good")

        let usable = QualityMetrics(
            coverageRatio: 0.8, meanSampleCount: 5, rmsResidualM: 0.02,
            holeRatio: 0.2, passCount: 2, qualityScore: 75
        )
        XCTAssertEqual(usable.label, "Usable")

        let thin = QualityMetrics(
            coverageRatio: 0.6, meanSampleCount: 3, rmsResidualM: 0.03,
            holeRatio: 0.4, passCount: 1, qualityScore: 55
        )
        XCTAssertEqual(thin.label, "Thin")

        let rescan = QualityMetrics(
            coverageRatio: 0.3, meanSampleCount: 2, rmsResidualM: 0.06,
            holeRatio: 0.7, passCount: 1, qualityScore: 40
        )
        XCTAssertEqual(rescan.label, "Rescan recommended")
        XCTAssertTrue(rescan.blocksUploadByDefault)
    }

    func testScoreFromHeightmap() {
        var cells: [DEMGridKey: DEMCellStats] = [:]
        for iz in 0..<4 {
            for ix in 0..<4 {
                var s = DEMCellStats()
                for _ in 0..<6 { s.addSample(1.0 + Double(ix) * 0.001) }
                cells[DEMGridKey(ix: ix, iz: iz)] = s
            }
        }
        let heightmap = DEMBuilder.buildHeightmap(cells: cells, cellSizeM: 0.05, minSamples: 3, fillOneCellGaps: false)!
        let metrics = QualityScorer.score(cells: cells, heightmap: heightmap, passCount: 2)
        XCTAssertGreaterThanOrEqual(metrics.qualityScore, 70)
        XCTAssertEqual(metrics.passCount, 2)
        XCTAssertGreaterThan(metrics.coverageRatio, 0.9)
    }
}
