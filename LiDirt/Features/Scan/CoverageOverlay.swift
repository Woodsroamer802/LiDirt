import SwiftUI

/// Coverage tint helper: green = well sampled, amber = thin, red/empty = missing.
enum CoverageOverlay {
    static func color(sampleCount: Int, minSamples: Int = DEMBuilder.defaultMinSamplesPerCell) -> Color {
        if sampleCount <= 0 {
            return LiDirtColors.coverageMissing.opacity(0.55)
        }
        if sampleCount < minSamples {
            return LiDirtColors.coverageThin.opacity(0.55)
        }
        if sampleCount < 6 {
            return LiDirtColors.coverageGood.opacity(0.45)
        }
        return LiDirtColors.coverageGood.opacity(0.65)
    }

    static func legendItems(minSamples: Int = DEMBuilder.defaultMinSamplesPerCell) -> [(Color, String)] {
        [
            (LiDirtColors.coverageGood, "Well sampled"),
            (LiDirtColors.coverageThin, "Thin (<\(minSamples))"),
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
                let tint = CoverageOverlay.color(sampleCount: count)
                // Approximate tint blend into grayscale for review preview.
                pixels[base] = gray
                pixels[base + 1] = UInt8(min(255, Int(gray) + (count >= 3 ? 20 : 0)))
                pixels[base + 2] = UInt8(max(0, Int(gray) - 10))
                pixels[base + 3] = 255
                _ = tint
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
