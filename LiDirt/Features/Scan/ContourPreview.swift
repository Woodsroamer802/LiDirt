import SwiftUI

/// Contour-line extraction from a DEM. Display / planning aid — not survey accuracy.
enum ContourPreview {
    static let defaultIntervalInches: Double = 0.125
    static let defaultIntervalMeters: Double = 0.003175

    /// Marching-squares segments in normalized grid coords (x = col, y = row; both 0…1).
    static func segments(
        heightmap: HeightmapResult,
        intervalM: Double = defaultIntervalMeters,
        maxLevels: Int = 80
    ) -> [CGPointPair] {
        localSegments(heightmap: heightmap, intervalM: intervalM, maxLevels: maxLevels)
            .map { seg in
                CGPointPair(
                    a: normalize(x: seg.ax, z: seg.az, heightmap: heightmap),
                    b: normalize(x: seg.bx, z: seg.bz, heightmap: heightmap)
                )
            }
    }

    /// Contour segments in local DEM meters (+X east / +Z north when north-aligned).
    static func localSegments(
        heightmap: HeightmapResult,
        intervalM: Double = defaultIntervalMeters,
        maxLevels: Int = 80
    ) -> [LocalContourSegment] {
        guard intervalM > 0, heightmap.width > 1, heightmap.height > 1 else { return [] }

        let minY = heightmap.bounds.minY
        let maxY = heightmap.bounds.maxY
        guard maxY > minY else { return [] }

        var levels: [Double] = []
        var level = (minY / intervalM).rounded(.down) * intervalM
        if abs(level - minY) < intervalM * 1e-6 {
            level += intervalM
        }
        while level < maxY && levels.count < maxLevels {
            levels.append(level)
            level += intervalM
        }
        guard !levels.isEmpty else { return [] }

        var out: [LocalContourSegment] = []
        let w = heightmap.width
        let h = heightmap.height
        let cell = heightmap.cellSizeM

        for row in 0..<(h - 1) {
            for col in 0..<(w - 1) {
                let i00 = row * w + col
                let i10 = row * w + col + 1
                let i01 = (row + 1) * w + col
                let i11 = (row + 1) * w + col + 1
                let v00 = heightmap.elevations[i00]
                let v10 = heightmap.elevations[i10]
                let v01 = heightmap.elevations[i01]
                let v11 = heightmap.elevations[i11]
                if v00.isNaN || v10.isNaN || v01.isNaN || v11.isNaN { continue }

                let x0 = heightmap.originX + Double(col) * cell
                let z0 = heightmap.originZ + Double(row) * cell

                for L in levels {
                    let lf = Float(L)
                    var caseIndex = 0
                    if v00 >= lf { caseIndex |= 1 }
                    if v10 >= lf { caseIndex |= 2 }
                    if v11 >= lf { caseIndex |= 4 }
                    if v01 >= lf { caseIndex |= 8 }
                    if caseIndex == 0 || caseIndex == 15 { continue }

                    let bottom = edgePoint(v00, v10, level: lf, x0: x0, z0: z0, edge: .bottom, cell: cell)
                    let right = edgePoint(v10, v11, level: lf, x0: x0, z0: z0, edge: .right, cell: cell)
                    let top = edgePoint(v01, v11, level: lf, x0: x0, z0: z0, edge: .top, cell: cell)
                    let left = edgePoint(v00, v01, level: lf, x0: x0, z0: z0, edge: .left, cell: cell)

                    switch caseIndex {
                    case 1, 14: appendPair(bottom, left, level: L, into: &out)
                    case 2, 13: appendPair(bottom, right, level: L, into: &out)
                    case 3, 12: appendPair(left, right, level: L, into: &out)
                    case 4, 11: appendPair(right, top, level: L, into: &out)
                    case 6, 9: appendPair(bottom, top, level: L, into: &out)
                    case 7, 8: appendPair(left, top, level: L, into: &out)
                    case 5:
                        // Ambiguous saddle — split into two segments.
                        appendPair(bottom, left, level: L, into: &out)
                        appendPair(right, top, level: L, into: &out)
                    case 10:
                        appendPair(bottom, right, level: L, into: &out)
                        appendPair(left, top, level: L, into: &out)
                    default:
                        break
                    }
                }
            }
        }
        return out
    }

    private enum Edge { case bottom, right, top, left }

    private static func edgePoint(
        _ a: Float,
        _ b: Float,
        level: Float,
        x0: Double,
        z0: Double,
        edge: Edge,
        cell: Double
    ) -> (Double, Double)? {
        guard crosses(a, b, level: level) else { return nil }
        let t = Double(interpolate(a, b, level: level))
        switch edge {
        case .bottom: return (x0 + t * cell, z0)
        case .right: return (x0 + cell, z0 + t * cell)
        case .top: return (x0 + t * cell, z0 + cell)
        case .left: return (x0, z0 + t * cell)
        }
    }

    private static func appendPair(
        _ p: (Double, Double)?,
        _ q: (Double, Double)?,
        level: Double,
        into: inout [LocalContourSegment]
    ) {
        guard let p, let q else { return }
        into.append(LocalContourSegment(ax: p.0, az: p.1, bx: q.0, bz: q.1, elevationM: level))
    }

    private static func normalize(x: Double, z: Double, heightmap: HeightmapResult) -> CGPoint {
        let spanX = max(heightmap.bounds.maxX - heightmap.bounds.minX, 1e-9)
        let spanZ = max(heightmap.bounds.maxZ - heightmap.bounds.minZ, 1e-9)
        return CGPoint(
            x: (x - heightmap.bounds.minX) / spanX,
            y: (z - heightmap.bounds.minZ) / spanZ
        )
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

struct LocalContourSegment: Equatable, Sendable {
    var ax: Double
    var az: Double
    var bx: Double
    var bz: Double
    var elevationM: Double
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
            for seg in segs {
                var path = Path()
                path.move(to: CGPoint(x: seg.a.x * size.width, y: (1 - seg.a.y) * size.height))
                path.addLine(to: CGPoint(x: seg.b.x * size.width, y: (1 - seg.b.y) * size.height))
                context.stroke(path, with: .color(LiDirtColors.constructionYellow.opacity(0.85)), lineWidth: 1)
            }
        }
        .accessibilityLabel("Contour preview at \(intervalInches) inch interval on smoothed DEM")
    }
}
