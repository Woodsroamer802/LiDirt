import Foundation

/// Applies proposed-grade cutouts onto an existing DEM (non-destructive: returns a new heightmap).
enum ProposedGradeApplicator {
    private static let cubicYardsPerCubicMeter = 1.3079506193143922

    static func apply(
        existing: HeightmapResult,
        cutouts: [GradeCutout],
        flaggedShapes: [FlagOutlinedShape] = []
    ) -> ProposedGradeResult {
        guard !cutouts.isEmpty || flaggedShapes.contains(where: { $0.flags.count >= 3 }) else {
            return ProposedGradeResult(
                existing: existing,
                proposed: existing,
                volume: ProposedGradeVolume(cutCubicYards: 0, fillCubicYards: 0, cellsEdited: 0)
            )
        }

        var proposedElev = existing.elevations
        var cutM3 = 0.0
        var fillM3 = 0.0
        var cellsEdited = 0
        let cellArea = existing.cellSizeM * existing.cellSizeM

        // Precompute absolute targets for level pads that use footprint mean.
        var resolvedTargets: [UUID: Float] = [:]
        for cutout in cutouts where cutout.mode == .setAbsoluteElevation {
            if let target = cutout.targetElevationM {
                resolvedTargets[cutout.id] = Float(target)
            } else {
                resolvedTargets[cutout.id] = meanElevation(in: cutout, heightmap: existing) ?? Float(existing.bounds.minY)
            }
        }
        for shape in flaggedShapes where shape.digMode == .setAbsoluteElevation && shape.flags.count >= 3 {
            if let target = shape.targetElevationM {
                resolvedTargets[shape.id] = Float(target)
            } else {
                resolvedTargets[shape.id] = meanElevation(inFlagRing: shape.flags, heightmap: existing)
                    ?? Float(existing.bounds.minY)
            }
        }

        for row in 0..<existing.height {
            for col in 0..<existing.width {
                let idx = row * existing.width + col
                let before = existing.elevations[idx]
                guard !before.isNaN else { continue }

                let x = existing.originX + (Double(col) + 0.5) * existing.cellSizeM
                let z = existing.originZ + (Double(row) + 0.5) * existing.cellSizeM

                var after = before
                var touched = false
                for cutout in cutouts {
                    guard cutout.contains(localX: x, localZ: z) else { continue }
                    touched = true
                    switch cutout.mode {
                    case .digBelowSurface:
                        after = min(after, before - Float(cutout.depthM))
                    case .setAbsoluteElevation:
                        if let target = resolvedTargets[cutout.id] {
                            after = target
                        }
                    }
                }
                for shape in flaggedShapes where shape.flags.count >= 3 {
                    guard ShapeFlagGeometry.contains(localX: x, localZ: z, ring: shape.flags) else { continue }
                    touched = true
                    switch shape.digMode {
                    case .digBelowSurface:
                        after = min(after, before - Float(shape.depthFeet * 0.3048))
                    case .setAbsoluteElevation:
                        if let target = resolvedTargets[shape.id] {
                            after = target
                        }
                    }
                }

                if touched, after != before {
                    proposedElev[idx] = after
                    cellsEdited += 1
                    let delta = Double(before - after) // + = cut
                    if delta > 0 {
                        cutM3 += delta * cellArea
                    } else if delta < 0 {
                        fillM3 += (-delta) * cellArea
                    }
                }
            }
        }

        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for e in proposedElev where !e.isNaN {
            minY = min(minY, Double(e))
            maxY = max(maxY, Double(e))
        }
        if minY > maxY {
            minY = existing.bounds.minY
            maxY = existing.bounds.maxY
        }

        let proposed = HeightmapResult(
            elevations: proposedElev,
            width: existing.width,
            height: existing.height,
            cellSizeM: existing.cellSizeM,
            originX: existing.originX,
            originZ: existing.originZ,
            sampleCounts: existing.sampleCounts,
            filledFlags: existing.filledFlags,
            bounds: HeightmapBounds(
                minX: existing.bounds.minX,
                maxX: existing.bounds.maxX,
                minZ: existing.bounds.minZ,
                maxZ: existing.bounds.maxZ,
                minY: minY,
                maxY: maxY
            )
        )

        return ProposedGradeResult(
            existing: existing,
            proposed: proposed,
            volume: ProposedGradeVolume(
                cutCubicYards: cutM3 * Self.cubicYardsPerCubicMeter,
                fillCubicYards: fillM3 * Self.cubicYardsPerCubicMeter,
                cellsEdited: cellsEdited
            )
        )
    }

    static func meanElevation(in cutout: GradeCutout, heightmap: HeightmapResult) -> Float? {
        meanElevation(where: { cutout.contains(localX: $0, localZ: $1) }, heightmap: heightmap)
    }

    static func meanElevation(inFlagRing flags: [ShapeFlag], heightmap: HeightmapResult) -> Float? {
        meanElevation(
            where: { ShapeFlagGeometry.contains(localX: $0, localZ: $1, ring: flags) },
            heightmap: heightmap
        )
    }

    private static func meanElevation(
        where predicate: (_ x: Double, _ z: Double) -> Bool,
        heightmap: HeightmapResult
    ) -> Float? {
        var sum: Double = 0
        var count = 0
        for row in 0..<heightmap.height {
            for col in 0..<heightmap.width {
                let idx = row * heightmap.width + col
                let elev = heightmap.elevations[idx]
                guard !elev.isNaN else { continue }
                let x = heightmap.originX + (Double(col) + 0.5) * heightmap.cellSizeM
                let z = heightmap.originZ + (Double(row) + 0.5) * heightmap.cellSizeM
                guard predicate(x, z) else { continue }
                sum += Double(elev)
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return Float(sum / Double(count))
    }

    /// Center of the DEM extent in local meters — default placement for a new cutout.
    static func defaultCenter(for heightmap: HeightmapResult) -> (x: Double, z: Double) {
        let x = heightmap.originX + Double(heightmap.width) * heightmap.cellSizeM * 0.5
        let z = heightmap.originZ + Double(heightmap.height) * heightmap.cellSizeM * 0.5
        return (x, z)
    }
}
