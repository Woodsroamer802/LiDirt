import XCTest
@testable import LiDirt

final class ProposedGradeApplicatorTests: XCTestCase {
    func testSlabLevelsFootprint() {
        let dem = makeFlatDEM(elev: 10, width: 20, height: 20, cell: 1)
        let center = ProposedGradeApplicator.defaultCenter(for: dem)
        let slab = GradeCutout.fromPreset(.concreteSlab, centerLocalX: center.x, centerLocalZ: center.z)
        // Force a known absolute target below the surface so cut volume is non-zero.
        var cut = slab
        cut.targetElevationM = 9.5
        cut.mode = .setAbsoluteElevation
        cut.widthFeet = 10 / 0.3048 * 0.5 // ~5 m wide-ish; use meters via feet conversion carefully
        // 6 m × 6 m rectangle in feet
        cut.widthFeet = 6 / 0.3048
        cut.lengthFeet = 6 / 0.3048

        let result = ProposedGradeApplicator.apply(existing: dem, cutouts: [cut])
        XCTAssertGreaterThan(result.volume.cellsEdited, 0)
        XCTAssertGreaterThan(result.volume.cutCubicYards, 0)
        // Center cell should be leveled.
        let mid = sample(result.proposed, x: center.x, z: center.z)
        XCTAssertEqual(mid ?? -1, 9.5, accuracy: 1e-3)
    }

    func testBasementDigsBelowSurface() {
        let dem = makeFlatDEM(elev: 5, width: 16, height: 16, cell: 1)
        let center = ProposedGradeApplicator.defaultCenter(for: dem)
        var basement = GradeCutout.fromPreset(.basement, centerLocalX: center.x, centerLocalZ: center.z)
        basement.widthFeet = 4 / 0.3048
        basement.lengthFeet = 4 / 0.3048
        basement.depthFeet = 8 // ~2.44 m

        let result = ProposedGradeApplicator.apply(existing: dem, cutouts: [basement])
        let mid = sample(result.proposed, x: center.x, z: center.z)
        XCTAssertEqual(mid ?? -1, Float(5 - 8 * 0.3048), accuracy: 0.05)
        XCTAssertGreaterThan(result.volume.cutCubicYards, 0)
    }

    func testPoolCircleCutout() {
        let dem = makeFlatDEM(elev: 2, width: 30, height: 30, cell: 0.5)
        let center = ProposedGradeApplicator.defaultCenter(for: dem)
        var pool = GradeCutout.fromPreset(.swimmingPool, centerLocalX: center.x, centerLocalZ: center.z)
        pool.widthFeet = 10 // diameter ~3 m
        pool.depthFeet = 5

        let result = ProposedGradeApplicator.apply(existing: dem, cutouts: [pool])
        XCTAssertGreaterThan(result.volume.cellsEdited, 10)
        let mid = sample(result.proposed, x: center.x, z: center.z)
        XCTAssertLessThan(mid ?? 99, 2)
    }

    func testFlagRingContainsAndCuts() {
        let dem = makeFlatDEM(elev: 3, width: 20, height: 20, cell: 1)
        let c = ProposedGradeApplicator.defaultCenter(for: dem)
        let ring = [
            ShapeFlag(label: "A", localX: c.x - 3, localY: 3, localZ: c.z - 3),
            ShapeFlag(label: "B", localX: c.x + 3, localY: 3, localZ: c.z - 3),
            ShapeFlag(label: "C", localX: c.x + 3, localY: 3, localZ: c.z + 3),
            ShapeFlag(label: "D", localX: c.x - 3, localY: 3, localZ: c.z + 3)
        ]
        XCTAssertTrue(ShapeFlagGeometry.contains(localX: c.x, localZ: c.z, ring: ring))
        XCTAssertFalse(ShapeFlagGeometry.contains(localX: c.x + 10, localZ: c.z, ring: ring))

        let shape = FlagOutlinedShape(flags: ring, digMode: .digBelowSurface, depthFeet: 4)
        let result = ProposedGradeApplicator.apply(existing: dem, cutouts: [], flaggedShapes: [shape])
        XCTAssertGreaterThan(result.volume.cellsEdited, 0)
        let mid = sample(result.proposed, x: c.x, z: c.z)
        XCTAssertEqual(mid ?? -1, Float(3 - 4 * 0.3048), accuracy: 0.05)
    }

    func testOppositeSpanScale() {
        let flags = [
            ShapeFlag(label: "A", localX: 0, localY: 0, localZ: 0),
            ShapeFlag(label: "B", localX: 10, localY: 0, localZ: 0),
            ShapeFlag(label: "C", localX: 10, localY: 0, localZ: 10),
            ShapeFlag(label: "D", localX: 0, localY: 0, localZ: 10)
        ]
        // Model A↔C diagonal ~14.14 m ≈ 46.4 ft; measure twice that → scale ~2
        let modelDiagFt = ShapeFlagGeometry.modelDistanceFeet(from: flags[0], to: flags[2])
        let shape = FlagOutlinedShape(
            flags: flags,
            measurements: [
                FlagSpanMeasurement(
                    fromFlagId: flags[0].id,
                    toFlagId: flags[2].id,
                    measuredFeet: modelDiagFt * 2,
                    kind: .opposite
                )
            ]
        )
        let scaled = ShapeFlagGeometry.applyOppositeSpanScale(shape)
        let newDiag = ShapeFlagGeometry.modelDistanceFeet(from: scaled.flags[0], to: scaled.flags[2])
        XCTAssertEqual(newDiag, modelDiagFt * 2, accuracy: 0.05)
    }

    func testMeshBuffersBuild() {
        let dem = makeFlatDEM(elev: 1, width: 8, height: 8, cell: 0.5)
        let buffers = TerrainMeshBuilder.buildBuffers(heightmap: dem)
        XCTAssertNotNil(buffers)
        XCTAssertFalse(buffers!.indices.isEmpty)
        XCTAssertEqual(buffers!.positions.count, 64)
    }

    private func makeFlatDEM(elev: Float, width: Int, height: Int, cell: Double) -> HeightmapResult {
        let elevations = [Float](repeating: elev, count: width * height)
        return HeightmapResult(
            elevations: elevations,
            width: width,
            height: height,
            cellSizeM: cell,
            originX: 0,
            originZ: 0,
            sampleCounts: [Int](repeating: 4, count: width * height),
            filledFlags: [Bool](repeating: false, count: width * height),
            bounds: HeightmapBounds(
                minX: 0,
                maxX: Double(width) * cell,
                minZ: 0,
                maxZ: Double(height) * cell,
                minY: Double(elev),
                maxY: Double(elev)
            )
        )
    }

    private func sample(_ hm: HeightmapResult, x: Double, z: Double) -> Float? {
        let col = Int(floor((x - hm.originX) / hm.cellSizeM))
        let row = Int(floor((z - hm.originZ) / hm.cellSizeM))
        guard col >= 0, row >= 0, col < hm.width, row < hm.height else { return nil }
        let v = hm.elevations[row * hm.width + col]
        return v.isNaN ? nil : v
    }
}
