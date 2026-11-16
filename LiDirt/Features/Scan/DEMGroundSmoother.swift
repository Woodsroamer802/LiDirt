import Foundation

/// Contour surface mode: keep as-scanned texture, or smooth gravel / veg / tire chew for planning maps.
enum ContourSurfaceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case asScanned
    case smoothedGround

    var id: String { rawValue }

    var label: String {
        switch self {
        case .asScanned: return "As-scanned"
        case .smoothedGround: return "Smoothed ground"
        }
    }

    var shortHelp: String {
        switch self {
        case .asScanned:
            return "Keep ruts, gravel texture, and fine roughness (as disturbed)."
        case .smoothedGround:
            return "Ignore fine noise — contours follow overall pad shape for equipment planning."
        }
    }
}

/// Filters high-frequency surface noise while preserving broad ground shape.
enum DEMGroundSmoother {
    /// Default neighborhood ~1.5 ft — larger than gravel, smaller than most pad swales.
    static let defaultRadiusM: Double = 0.4572
    /// Spike threshold vs local median (~1.25 in).
    static let defaultSpikeThresholdM: Double = 0.03175

    static func prepareForContours(
        _ heightmap: HeightmapResult,
        mode: ContourSurfaceMode,
        radiusM: Double = defaultRadiusM,
        spikeThresholdM: Double = defaultSpikeThresholdM
    ) -> HeightmapResult {
        switch mode {
        case .asScanned:
            return heightmap
        case .smoothedGround:
            return smooth(heightmap, radiusM: radiusM, spikeThresholdM: spikeThresholdM)
        }
    }

    /// Median filter + optional spike clamp, then a light mean pass in the same neighborhood.
    static func smooth(
        _ heightmap: HeightmapResult,
        radiusM: Double = defaultRadiusM,
        spikeThresholdM: Double = defaultSpikeThresholdM
    ) -> HeightmapResult {
        let radiusCells = max(1, Int(ceil(radiusM / max(heightmap.cellSizeM, 1e-6))))
        let medians = neighborhoodReduce(heightmap, radiusCells: radiusCells, reducer: .median)
        var cleaned = heightmap.elevations
        for i in cleaned.indices {
            let original = cleaned[i]
            let median = medians[i]
            if original.isNaN || median.isNaN { continue }
            if abs(original - median) > Float(spikeThresholdM) {
                cleaned[i] = median
            }
        }
        let cleanedMap = replacingElevations(heightmap, cleaned)
        let means = neighborhoodReduce(cleanedMap, radiusCells: radiusCells, reducer: .mean)
        return replacingElevations(cleanedMap, means)
    }

    private enum Reducer { case median, mean }

    private static func neighborhoodReduce(
        _ heightmap: HeightmapResult,
        radiusCells: Int,
        reducer: Reducer
    ) -> [Float] {
        let w = heightmap.width
        let h = heightmap.height
        var out = [Float](repeating: .nan, count: w * h)
        var window: [Float] = []
        window.reserveCapacity((radiusCells * 2 + 1) * (radiusCells * 2 + 1))

        for row in 0..<h {
            for col in 0..<w {
                let idx = row * w + col
                if heightmap.elevations[idx].isNaN { continue }
                window.removeAll(keepingCapacity: true)
                for dr in -radiusCells...radiusCells {
                    for dc in -radiusCells...radiusCells {
                        let r = row + dr
                        let c = col + dc
                        guard r >= 0, c >= 0, r < h, c < w else { continue }
                        let v = heightmap.elevations[r * w + c]
                        if !v.isNaN { window.append(v) }
                    }
                }
                guard !window.isEmpty else { continue }
                switch reducer {
                case .median:
                    window.sort()
                    out[idx] = window[window.count / 2]
                case .mean:
                    let sum = window.reduce(0, +)
                    out[idx] = sum / Float(window.count)
                }
            }
        }
        return out
    }

    private static func replacingElevations(_ heightmap: HeightmapResult, _ elevations: [Float]) -> HeightmapResult {
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for v in elevations where !v.isNaN {
            minY = min(minY, Double(v))
            maxY = max(maxY, Double(v))
        }
        var bounds = heightmap.bounds
        bounds.minY = minY == .greatestFiniteMagnitude ? heightmap.bounds.minY : minY
        bounds.maxY = maxY == -.greatestFiniteMagnitude ? heightmap.bounds.maxY : maxY
        return HeightmapResult(
            elevations: elevations,
            width: heightmap.width,
            height: heightmap.height,
            cellSizeM: heightmap.cellSizeM,
            originX: heightmap.originX,
            originZ: heightmap.originZ,
            sampleCounts: heightmap.sampleCounts,
            filledFlags: heightmap.filledFlags,
            bounds: bounds
        )
    }
}
