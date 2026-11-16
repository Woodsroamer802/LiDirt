import XCTest
@testable import LiDirt

final class MetadataCodecTests: XCTestCase {
    func testEncodeDecodeSchemaVersion1() throws {
        var cells: [DEMGridKey: DEMCellStats] = [:]
        for iz in 0..<2 {
            for ix in 0..<3 {
                var s = DEMCellStats()
                for _ in 0..<4 { s.addSample(0.25) }
                cells[DEMGridKey(ix: ix, iz: iz)] = s
            }
        }
        let heightmap = DEMBuilder.buildHeightmap(cells: cells, cellSizeM: 0.05)!
        let metrics = QualityScorer.score(cells: cells, heightmap: heightmap, passCount: 2)

        let scanId = UUID()
        let projectId = UUID()
        let metadata = ScanPackageWriter.makeMetadata(
            scanId: scanId,
            projectId: projectId,
            heightmap: heightmap,
            metrics: metrics,
            durationSec: 42,
            minSamplesPerCell: 3,
            preferredContourIntervalInches: 0.125,
            controlPointsCount: 1,
            hasLiDAR: true
        )

        XCTAssertEqual(metadata.schemaVersion, 1)
        XCTAssertEqual(metadata.frame.upAxis, "y")
        XCTAssertEqual(metadata.frame.cellSizeM, 0.05)
        XCTAssertEqual(metadata.display.preferredContourIntervalInches, 0.125)
        XCTAssertEqual(metadata.display.productLanguage, "field_grade_volume_estimating")
        XCTAssertTrue(metadata.disclaimer.contains("Not a certified survey"))

        let data = try ScanPackageWriter.encodeMetadata(metadata)
        let decoded = try ScanPackageWriter.decodeMetadata(from: data)
        XCTAssertEqual(decoded, metadata)
        XCTAssertEqual(decoded.scanId, scanId.uuidString)
        XCTAssertEqual(decoded.georef.method, "none")
        XCTAssertEqual(decoded.georef.heading.source, "unavailable")
        XCTAssertFalse(decoded.frame.alignedToNorth)
        XCTAssertEqual(decoded.frame.rowDirection, "+Z")
        XCTAssertEqual(decoded.frame.columnDirection, "+X")
    }

    func testHeightmapBinaryRoundTripNaN() throws {
        let elevations: [Float] = [1.0, .nan, 2.5, 3.0]
        // Must work with a let array — no mutable buffer required for heightmap.f32.
        let data = ScanPackageWriter.float32BinaryData(elevations)
        XCTAssertEqual(data.count, elevations.count * MemoryLayout<Float>.size)

        let restored: [Float] = data.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Float.self))
        }
        XCTAssertEqual(restored[0], 1.0)
        XCTAssertTrue(restored[1].isNaN)
        XCTAssertEqual(restored[2], 2.5)
        XCTAssertEqual(restored[3], 3.0)
    }

    func testWritePackageUsesLetSafeFloatBinary() throws {
        var cells: [DEMGridKey: DEMCellStats] = [:]
        for iz in 0..<2 {
            for ix in 0..<2 {
                var s = DEMCellStats()
                s.addSample(Float(ix + iz))
                cells[DEMGridKey(ix: ix, iz: iz)] = s
            }
        }
        let heightmap = try XCTUnwrap(DEMBuilder.buildHeightmap(cells: cells, cellSizeM: 0.05))
        let metrics = QualityScorer.score(cells: cells, heightmap: heightmap, passCount: 1)
        let metadata = ScanPackageWriter.makeMetadata(
            scanId: UUID(),
            projectId: UUID(),
            heightmap: heightmap,
            metrics: metrics,
            durationSec: 1,
            minSamplesPerCell: 1,
            preferredContourIntervalInches: 0.125,
            controlPointsCount: 0,
            hasLiDAR: true
        )

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidirt-package-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let package = try ScanPackageWriter.writePackage(
            to: dir,
            metadata: metadata,
            heightmap: heightmap
        )

        let onDisk = try Data(contentsOf: package.heightmapURL)
        XCTAssertEqual(onDisk, ScanPackageWriter.float32BinaryData(heightmap.elevations))
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.metadataURL.path))
    }
}
