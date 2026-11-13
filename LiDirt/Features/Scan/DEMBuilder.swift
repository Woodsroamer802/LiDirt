import Foundation
import simd

/// Mutable cell statistics for multi-pass averaging. Pure value math — no ARKit types.
struct DEMCellStats: Sendable, Equatable {
    var sumZ: Double = 0
    var sumZ2: Double = 0
    var count: Int = 0
    var lastUpdated: Date = .distantPast

    mutating func addSample(_ elevation: Double, at date: Date = Date()) {
        sumZ += elevation
        sumZ2 += elevation * elevation
        count += 1
        lastUpdated = date
    }

    var mean: Double? {
        guard count > 0 else { return nil }
        return sumZ / Double(count)
    }

    var variance: Double? {
        guard count > 0, let mean else { return nil }
        let v = sumZ2 / Double(count) - mean * mean
        return max(0, v)
    }
}

struct DEMGridKey: Hashable, Sendable {
    var ix: Int
    var iz: Int
}

/// Accumulates world-space samples into a horizontal DEM grid (ARKit +Y up → elevation = Y).
final class DEMAccumulator: @unchecked Sendable {
    let cellSizeM: Double
    private(set) var cells: [DEMGridKey: DEMCellStats] = [:]
    private let lock = NSLock()

    init(cellSizeM: Double = 0.05) {
        self.cellSizeM = cellSizeM
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        cells.removeAll(keepingCapacity: true)
    }

    func addSample(x: Double, y: Double, z: Double, at date: Date = Date()) {
        let ix = Int(floor(x / cellSizeM))
        let iz = Int(floor(z / cellSizeM))
        let key = DEMGridKey(ix: ix, iz: iz)
        lock.lock()
        defer { lock.unlock() }
        var stats = cells[key] ?? DEMCellStats()
        stats.addSample(y, at: date)
        cells[key] = stats
    }

    func addSamples(_ points: [SIMD3<Float>], at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        for p in points {
            let ix = Int(floor(Double(p.x) / cellSizeM))
            let iz = Int(floor(Double(p.z) / cellSizeM))
            let key = DEMGridKey(ix: ix, iz: iz)
            var stats = cells[key] ?? DEMCellStats()
            stats.addSample(Double(p.y), at: date)
            cells[key] = stats
        }
    }

    func snapshot() -> [DEMGridKey: DEMCellStats] {
        lock.lock()
        defer { lock.unlock() }
        return cells
    }

    var filledCellCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cells.count
    }
}

struct HeightmapBounds: Equatable, Sendable {
    var minX: Double
    var maxX: Double
    var minZ: Double
    var maxZ: Double
    var minY: Double
    var maxY: Double
}

struct HeightmapResult: Sendable {
    /// Row-major float32 elevations (Y). NaN = hole.
    var elevations: [Float]
    var width: Int
    var height: Int
    var cellSizeM: Double
    var originX: Double
    var originZ: Double
    /// Per-cell sample counts aligned with elevations (0 for holes before optional fill).
    var sampleCounts: [Int]
    /// True where a 1-cell gap was neighbor-filled for preview only.
    var filledFlags: [Bool]
    var bounds: HeightmapBounds
}

enum DEMBuilder {
    static let defaultMinSamplesPerCell = 3

    /// Build a heightmap from accumulated cell stats.
    /// - Parameters:
    ///   - minSamples: cells below this become NaN holes.
    ///   - fillOneCellGaps: optional preview-only neighbor average for single-cell holes.
    static func buildHeightmap(
        cells: [DEMGridKey: DEMCellStats],
        cellSizeM: Double,
        minSamples: Int = defaultMinSamplesPerCell,
        fillOneCellGaps: Bool = true
    ) -> HeightmapResult? {
        let qualifying = cells.filter { $0.value.count >= minSamples }
        guard !qualifying.isEmpty else { return nil }

        let ixs = qualifying.keys.map(\.ix)
        let izs = qualifying.keys.map(\.iz)
        guard let minIX = ixs.min(), let maxIX = ixs.max(),
              let minIZ = izs.min(), let maxIZ = izs.max() else {
            return nil
        }

        let width = maxIX - minIX + 1
        let height = maxIZ - minIZ + 1
        var elevations = [Float](repeating: .nan, count: width * height)
        var sampleCounts = [Int](repeating: 0, count: width * height)
        var filledFlags = [Bool](repeating: false, count: width * height)

        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for (key, stats) in qualifying {
            guard let mean = stats.mean else { continue }
            let col = key.ix - minIX
            let row = key.iz - minIZ
            let idx = row * width + col
            elevations[idx] = Float(mean)
            sampleCounts[idx] = stats.count
            minY = min(minY, mean)
            maxY = max(maxY, mean)
        }

        if fillOneCellGaps {
            fillSingleCellGaps(
                elevations: &elevations,
                sampleCounts: sampleCounts,
                filledFlags: &filledFlags,
                width: width,
                height: height,
                minY: &minY,
                maxY: &maxY
            )
        }

        let originX = Double(minIX) * cellSizeM
        let originZ = Double(minIZ) * cellSizeM
        let bounds = HeightmapBounds(
            minX: originX,
            maxX: originX + Double(width) * cellSizeM,
            minZ: originZ,
            maxZ: originZ + Double(height) * cellSizeM,
            minY: minY == .greatestFiniteMagnitude ? 0 : minY,
            maxY: maxY == -.greatestFiniteMagnitude ? 0 : maxY
        )

        return HeightmapResult(
            elevations: elevations,
            width: width,
            height: height,
            cellSizeM: cellSizeM,
            originX: originX,
            originZ: originZ,
            sampleCounts: sampleCounts,
            filledFlags: filledFlags,
            bounds: bounds
        )
    }

    /// Convex-hull-ish coverage: cells inside axis-aligned bounding box of qualifying samples.
    static func hullCellCount(width: Int, height: Int) -> Int {
        max(1, width * height)
    }

    private static func fillSingleCellGaps(
        elevations: inout [Float],
        sampleCounts: [Int],
        filledFlags: inout [Bool],
        width: Int,
        height: Int,
        minY: inout Double,
        maxY: inout Double
    ) {
        let original = elevations
        for row in 0..<height {
            for col in 0..<width {
                let idx = row * width + col
                if !original[idx].isNaN { continue }

                var sum: Float = 0
                var n = 0
                let neighbors = [(col - 1, row), (col + 1, row), (col, row - 1), (col, row + 1)]
                for (nx, ny) in neighbors {
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let nidx = ny * width + nx
                    let v = original[nidx]
                    if !v.isNaN {
                        sum += v
                        n += 1
                    }
                }
                // Only fill true 1-cell gaps: at least 3 of 4 cardinal neighbors present.
                if n >= 3 {
                    let mean = sum / Float(n)
                    elevations[idx] = mean
                    filledFlags[idx] = true
                    minY = min(minY, Double(mean))
                    maxY = max(maxY, Double(mean))
                }
            }
        }
    }
}
