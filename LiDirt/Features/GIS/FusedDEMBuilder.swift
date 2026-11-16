import Foundation

struct FusedDEMResult: Sendable {
    var heightmap: HeightmapResult
    /// Added to LiDAR relative elevations so they sit on the USGS absolute surface.
    var verticalBiasM: Double
    var foundationSampleCount: Int
    var lidarSampleCount: Int
    var method: String
}

/// Combines a USGS 3DEP foundation DEM with a phone LiDAR DEM for equipment-grade detail.
enum FusedDEMBuilder {
    /// Fuse at LiDAR cell size over the foundation footprint.
    /// Inside the LiDAR hull, LiDAR (+ vertical bias) replaces foundation; edges feather over `featherMeters`.
    static func fuse(
        foundation: HeightmapResult,
        lidar: HeightmapResult,
        featherMeters: Double = 2.0
    ) -> FusedDEMResult {
        let cell = lidar.cellSizeM
        let minX = foundation.bounds.minX
        let maxX = foundation.bounds.maxX
        let minZ = foundation.bounds.minZ
        let maxZ = foundation.bounds.maxZ
        let width = max(2, Int(ceil((maxX - minX) / cell)))
        let height = max(2, Int(ceil((maxZ - minZ) / cell)))

        let bias = verticalBias(foundation: foundation, lidar: lidar)
        var elevations = [Float](repeating: .nan, count: width * height)
        var sampleCounts = [Int](repeating: 0, count: width * height)
        var filledFlags = [Bool](repeating: false, count: width * height)
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        var foundationCount = 0
        var lidarCount = 0

        let feather = max(featherMeters, cell)

        for row in 0..<height {
            for col in 0..<width {
                let x = minX + (Double(col) + 0.5) * cell
                let z = minZ + (Double(row) + 0.5) * cell
                let foundationElev = sampleBilinear(foundation, x: x, z: z)
                let lidarElev = sampleNearest(lidar, x: x, z: z)
                let idx = row * width + col

                if let lidarElev, let foundationElev {
                    let distance = distanceOutsideLidarValid(lidar, x: x, z: z)
                    let weight: Double
                    if distance <= 0 {
                        weight = 1
                    } else if distance >= feather {
                        weight = 0
                    } else {
                        weight = 1 - (distance / feather)
                    }
                    let fused = foundationElev * (1 - weight) + (lidarElev + bias) * weight
                    elevations[idx] = Float(fused)
                    sampleCounts[idx] = weight > 0.5 ? 8 : 1
                    filledFlags[idx] = weight > 0 && weight < 1
                    minY = min(minY, fused)
                    maxY = max(maxY, fused)
                    if weight > 0.5 { lidarCount += 1 } else { foundationCount += 1 }
                } else if let lidarElev {
                    let fused = lidarElev + bias
                    elevations[idx] = Float(fused)
                    sampleCounts[idx] = 8
                    minY = min(minY, fused)
                    maxY = max(maxY, fused)
                    lidarCount += 1
                } else if let foundationElev {
                    elevations[idx] = Float(foundationElev)
                    sampleCounts[idx] = 1
                    minY = min(minY, foundationElev)
                    maxY = max(maxY, foundationElev)
                    foundationCount += 1
                }
            }
        }

        let heightmap = HeightmapResult(
            elevations: elevations,
            width: width,
            height: height,
            cellSizeM: cell,
            originX: minX,
            originZ: minZ,
            sampleCounts: sampleCounts,
            filledFlags: filledFlags,
            bounds: HeightmapBounds(
                minX: minX,
                maxX: minX + Double(width) * cell,
                minZ: minZ,
                maxZ: minZ + Double(height) * cell,
                minY: minY == .greatestFiniteMagnitude ? 0 : minY,
                maxY: maxY == -.greatestFiniteMagnitude ? 0 : maxY
            )
        )

        return FusedDEMResult(
            heightmap: heightmap,
            verticalBiasM: bias,
            foundationSampleCount: foundationCount,
            lidarSampleCount: lidarCount,
            method: "usgs_3dep_plus_lidar"
        )
    }

    /// Mean(foundation − lidar) over overlapping valid cells → add to LiDAR for absolute match.
    static func verticalBias(foundation: HeightmapResult, lidar: HeightmapResult) -> Double {
        var sum = 0.0
        var n = 0
        for row in 0..<lidar.height {
            for col in 0..<lidar.width {
                let elev = lidar.elevations[row * lidar.width + col]
                guard !elev.isNaN else { continue }
                let x = lidar.originX + (Double(col) + 0.5) * lidar.cellSizeM
                let z = lidar.originZ + (Double(row) + 0.5) * lidar.cellSizeM
                guard let foundationElev = sampleBilinear(foundation, x: x, z: z) else { continue }
                sum += foundationElev - Double(elev)
                n += 1
            }
        }
        guard n > 0 else { return 0 }
        return sum / Double(n)
    }

    static func sampleBilinear(_ dem: HeightmapResult, x: Double, z: Double) -> Double? {
        let colF = (x - dem.originX) / dem.cellSizeM - 0.5
        let rowF = (z - dem.originZ) / dem.cellSizeM - 0.5
        let c0 = Int(floor(colF))
        let r0 = Int(floor(rowF))
        let c1 = c0 + 1
        let r1 = r0 + 1
        guard c0 >= 0, r0 >= 0, c1 < dem.width, r1 < dem.height else {
            return sampleNearest(dem, x: x, z: z)
        }
        let tx = colF - Double(c0)
        let ty = rowF - Double(r0)
        let v00 = dem.elevations[r0 * dem.width + c0]
        let v10 = dem.elevations[r0 * dem.width + c1]
        let v01 = dem.elevations[r1 * dem.width + c0]
        let v11 = dem.elevations[r1 * dem.width + c1]
        if v00.isNaN || v10.isNaN || v01.isNaN || v11.isNaN {
            return sampleNearest(dem, x: x, z: z)
        }
        let a = Double(v00) * (1 - tx) + Double(v10) * tx
        let b = Double(v01) * (1 - tx) + Double(v11) * tx
        return a * (1 - ty) + b * ty
    }

    static func sampleNearest(_ dem: HeightmapResult, x: Double, z: Double) -> Double? {
        let col = Int(floor((x - dem.originX) / dem.cellSizeM))
        let row = Int(floor((z - dem.originZ) / dem.cellSizeM))
        guard col >= 0, row >= 0, col < dem.width, row < dem.height else { return nil }
        let v = dem.elevations[row * dem.width + col]
        return v.isNaN ? nil : Double(v)
    }

    /// Approximate distance outside the LiDAR valid hull (0 = inside / on valid cell).
    private static func distanceOutsideLidarValid(_ lidar: HeightmapResult, x: Double, z: Double) -> Double {
        if sampleNearest(lidar, x: x, z: z) != nil { return 0 }
        let search = max(Int(ceil(4.0 / lidar.cellSizeM)), 2)
        var best = Double.greatestFiniteMagnitude
        let col0 = Int(floor((x - lidar.originX) / lidar.cellSizeM))
        let row0 = Int(floor((z - lidar.originZ) / lidar.cellSizeM))
        for dr in -search...search {
            for dc in -search...search {
                let col = col0 + dc
                let row = row0 + dr
                guard col >= 0, row >= 0, col < lidar.width, row < lidar.height else { continue }
                let v = lidar.elevations[row * lidar.width + col]
                guard !v.isNaN else { continue }
                let cx = lidar.originX + (Double(col) + 0.5) * lidar.cellSizeM
                let cz = lidar.originZ + (Double(row) + 0.5) * lidar.cellSizeM
                let d = hypot(x - cx, z - cz)
                best = min(best, d)
            }
        }
        return best == .greatestFiniteMagnitude ? 1_000 : best
    }
}
