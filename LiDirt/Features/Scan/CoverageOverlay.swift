import SwiftUI

/// Coverage goals for HUD tint. Green means the sample goal is met — not merely “has any samples.”
enum CoverageGoals {
    /// Minimum samples before a cell contributes to the DEM (holes otherwise).
    static let minSamplesForDEM = DEMBuilder.defaultMinSamplesPerCell
    /// Samples required before a cell is tinted green (“goal met”).
    /// Aligns with the quality scorer’s strong sample target (~8).
    static let samplesForGoalMet = 8
}

/// Coverage tint helper: green = goal met, amber = incomplete, red = missing.
enum CoverageOverlay {
    enum Level: Equatable {
        case missing
        case incomplete
        case goalMet
    }

    static func level(
        sampleCount: Int,
        goalSamples: Int = CoverageGoals.samplesForGoalMet
    ) -> Level {
        if sampleCount <= 0 { return .missing }
        if sampleCount < goalSamples { return .incomplete }
        return .goalMet
    }

    static func color(
        sampleCount: Int,
        goalSamples: Int = CoverageGoals.samplesForGoalMet
    ) -> Color {
        switch level(sampleCount: sampleCount, goalSamples: goalSamples) {
        case .missing:
            return LiDirtColors.coverageMissing.opacity(0.55)
        case .incomplete:
            // Amber = seen but not yet at goal (do not use green for “has samples”).
            return LiDirtColors.coverageThin.opacity(0.60)
        case .goalMet:
            return LiDirtColors.coverageGood.opacity(0.65)
        }
    }

    static func legendItems(goalSamples: Int = CoverageGoals.samplesForGoalMet) -> [(Color, String)] {
        [
            (LiDirtColors.coverageGood, "Goal met (≥\(goalSamples))"),
            (LiDirtColors.coverageThin, "Incomplete"),
            (LiDirtColors.coverageMissing, "Missing")
        ]
    }
}

struct CoverageLegendView: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(CoverageOverlay.legendItems(), id: \.1) { item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(item.0)
                        .frame(width: 8, height: 8)
                    Text(item.1)
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textSecondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct HeightmapPreviewImage {
    static func cgImage(from heightmap: HeightmapResult) -> CGImage? {
        let w = heightmap.width
        let h = heightmap.height
        guard w > 0, h > 0 else { return nil }

        var minV = Float.greatestFiniteMagnitude
        var maxV = -Float.greatestFiniteMagnitude
        for v in heightmap.elevations where !v.isNaN {
            minV = min(minV, v)
            maxV = max(maxV, v)
        }
        if !minV.isFinite || !maxV.isFinite || maxV <= minV {
            minV = 0
            maxV = 1
        }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let elev = heightmap.elevations[i]
            let count = heightmap.sampleCounts[i]
            let base = i * 4
            if elev.isNaN {
                pixels[base] = 40
                pixels[base + 1] = 40
                pixels[base + 2] = 45
                pixels[base + 3] = 255
            } else {
                let t = (elev - minV) / (maxV - minV)
                let gray = UInt8(clamping: Int(t * 200) + 40)
                switch CoverageOverlay.level(sampleCount: count) {
                case .goalMet:
                    pixels[base] = UInt8(max(0, Int(gray) - 30))
                    pixels[base + 1] = UInt8(min(255, Int(gray) + 40))
                    pixels[base + 2] = UInt8(max(0, Int(gray) - 20))
                case .incomplete:
                    pixels[base] = UInt8(min(255, Int(gray) + 40))
                    pixels[base + 1] = UInt8(min(255, Int(gray) + 20))
                    pixels[base + 2] = UInt8(max(0, Int(gray) - 30))
                case .missing:
                    pixels[base] = gray
                    pixels[base + 1] = gray
                    pixels[base + 2] = gray
                }
                pixels[base + 3] = 255
            }
        }

        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
