import Foundation

struct QualityMetrics: Equatable, Sendable {
    var coverageRatio: Double
    var meanSampleCount: Double
    var rmsResidualM: Double
    var holeRatio: Double
    var passCount: Int
    var qualityScore: Int

    var label: String {
        switch qualityScore {
        case 90...: return "Good"
        case 70..<90: return "Usable"
        case 50..<70: return "Thin"
        default: return "Rescan recommended"
        }
    }

    var blocksUploadByDefault: Bool {
        qualityScore < 50
    }
}

enum QualityScorer {
    /// score = 100
    ///   - 40 * holeRatio
    ///   - 30 * clamp(rmsResidualM / 0.05, 0, 1)
    ///   - 20 * (1 - clamp(meanSampleCount / 8, 0, 1))
    ///   - 10 * (passCount < 2 ? 1 : 0)
    static func score(
        cells: [DEMGridKey: DEMCellStats],
        heightmap: HeightmapResult?,
        passCount: Int,
        minSamples: Int = DEMBuilder.defaultMinSamplesPerCell
    ) -> QualityMetrics {
        guard let heightmap, heightmap.width > 0, heightmap.height > 0 else {
            return QualityMetrics(
                coverageRatio: 0,
                meanSampleCount: 0,
                rmsResidualM: 0,
                holeRatio: 1,
                passCount: passCount,
                qualityScore: 0
            )
        }

        let hull = DEMBuilder.hullCellCount(width: heightmap.width, height: heightmap.height)
        var filled = 0
        var holes = 0
        for (i, elev) in heightmap.elevations.enumerated() {
            if elev.isNaN {
                holes += 1
            } else if !heightmap.filledFlags[i] {
                filled += 1
            } else {
                // Preview-filled cells count as holes for honest coverage.
                holes += 1
            }
        }

        let coverageRatio = Double(filled) / Double(hull)
        let holeRatio = Double(holes) / Double(hull)

        let qualifying = cells.values.filter { $0.count >= minSamples }
        let meanSampleCount: Double
        if qualifying.isEmpty {
            meanSampleCount = 0
        } else {
            meanSampleCount = qualifying.map { Double($0.count) }.reduce(0, +) / Double(qualifying.count)
        }

        let multi = qualifying.filter { $0.count >= 2 }
        let rmsResidualM: Double
        if multi.isEmpty {
            rmsResidualM = 0
        } else {
            let meanVar = multi.compactMap(\.variance).reduce(0, +) / Double(multi.count)
            rmsResidualM = sqrt(max(0, meanVar))
        }

        let scoreValue = computeScore(
            holeRatio: holeRatio,
            rmsResidualM: rmsResidualM,
            meanSampleCount: meanSampleCount,
            passCount: passCount
        )

        return QualityMetrics(
            coverageRatio: coverageRatio,
            meanSampleCount: meanSampleCount,
            rmsResidualM: rmsResidualM,
            holeRatio: holeRatio,
            passCount: passCount,
            qualityScore: scoreValue
        )
    }

    static func computeScore(
        holeRatio: Double,
        rmsResidualM: Double,
        meanSampleCount: Double,
        passCount: Int
    ) -> Int {
        let holePenalty = 40 * clamp(holeRatio, 0, 1)
        let rmsPenalty = 30 * clamp(rmsResidualM / 0.05, 0, 1)
        let samplePenalty = 20 * (1 - clamp(meanSampleCount / 8, 0, 1))
        let passPenalty = passCount < 2 ? 10.0 : 0.0
        let raw = 100 - holePenalty - rmsPenalty - samplePenalty - passPenalty
        return Int(clamp(raw, 0, 100).rounded())
    }

    private static func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, value))
    }
}
