import SwiftUI

/// Lightweight contour-line preview from a DEM. Display hook only — not survey accuracy.
enum ContourPreview {
    static let defaultIntervalInches: Double = 0.125
    static let defaultIntervalMeters: Double = 0.003175

    /// Marching-squares-lite: emit horizontal/vertical segments where elevation crosses levels.
    static func segments(
        heightmap: HeightmapResult,
        intervalM: Double = defaultIntervalMeters,
        maxLevels: Int = 40
    ) -> [CGPointPair] {
        guard intervalM > 0, heightmap.width > 1, heightmap.height > 1 else { return [] }

        let minY = heightmap.bounds.minY
        let maxY = heightmap.bounds.maxY
        guard maxY > minY else { return [] }

        var levels: [Double] = []
        var level = (minY / intervalM).rounded(.down) * intervalM
        while level <= maxY && levels.count < maxLevels {
            levels.append(level)
            level += intervalM
        }

        var pairs: [CGPointPair] = []
        let w = heightmap.width
        let h = heightmap.height

        for row in 0..<(h - 1) {
            for col in 0..<(w - 1) {
                let i00 = row * w + col
                let i10 = row * w + col + 1
                let i01 = (row + 1) * w + col
                let v00 = heightmap.elevations[i00]
                let v10 = heightmap.elevations[i10]
                let v01 = heightmap.elevations[i01]
                if v00.isNaN || v10.isNaN || v01.isNaN { continue }

                for L in levels {
                    if crosses(v00, v10, level: Float(L)) {
                        let t = interpolate(v00, v10, level: Float(L))
                        let yNorm = CGFloat(row) / CGFloat(h - 1)
                        pairs.append(CGPointPair(
                            a: CGPoint(x: (CGFloat(col) + t) / CGFloat(w - 1), y: yNorm),
                            b: CGPoint(x: (CGFloat(col) + t) / CGFloat(w - 1), y: yNorm)
                        ))
                    }
                    if crosses(v00, v01, level: Float(L)) {
                        let t = interpolate(v00, v01, level: Float(L))
                        let xNorm = CGFloat(col) / CGFloat(w - 1)
                        pairs.append(CGPointPair(
                            a: CGPoint(x: xNorm, y: (CGFloat(row) + t) / CGFloat(h - 1)),
                            b: CGPoint(x: xNorm, y: (CGFloat(row) + t) / CGFloat(h - 1))
                        ))
                    }
                }
            }
        }
        return pairs
    }

    private static func crosses(_ a: Float, _ b: Float, level: Float) -> Bool {
        (a < level && b >= level) || (b < level && a >= level)
    }

    private static func interpolate(_ a: Float, _ b: Float, level: Float) -> CGFloat {
        let d = b - a
        guard abs(d) > 1e-6 else { return 0.5 }
        return CGFloat((level - a) / d)
    }
}

struct CGPointPair: Equatable {
    var a: CGPoint
    var b: CGPoint
}

struct ContourPreviewCanvas: View {
    let heightmap: HeightmapResult
    var intervalInches: Double = ContourPreview.defaultIntervalInches

    var body: some View {
        Canvas { context, size in
            let intervalM = intervalInches * 0.0254
            let segs = ContourPreview.segments(heightmap: heightmap, intervalM: intervalM)
            var path = Path()
            for seg in segs {
                let p = CGPoint(x: seg.a.x * size.width, y: (1 - seg.a.y) * size.height)
                path.addEllipse(in: CGRect(x: p.x - 0.5, y: p.y - 0.5, width: 1, height: 1))
            }
            context.stroke(path, with: .color(LiDirtColors.constructionYellow.opacity(0.7)), lineWidth: 1)
        }
        .accessibilityLabel("Contour preview at \(intervalInches) inch interval on smoothed DEM")
    }
}
