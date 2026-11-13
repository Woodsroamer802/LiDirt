import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct ScanMetadata: Codable, Equatable, Sendable {
    struct DeviceInfo: Codable, Equatable, Sendable {
        var model: String
        var osVersion: String
        var hasLiDAR: Bool
    }

    struct Vec3: Codable, Equatable, Sendable {
        var x: Double
        var y: Double
        var z: Double
    }

    struct FrameInfo: Codable, Equatable, Sendable {
        var upAxis: String
        var units: String
        var origin: Vec3
        var cellSizeM: Double
        var width: Int
        var height: Int
        var boundsMin: Vec3
        var boundsMax: Vec3
        var rowDirection: String
        var columnDirection: String
    }

    struct CaptureInfo: Codable, Equatable, Sendable {
        var passCount: Int
        var durationSec: Double
        var minSamplesPerCell: Int
    }

    struct QualityInfo: Codable, Equatable, Sendable {
        var qualityScore: Int
        var coverageRatio: Double
        var holeRatio: Double
        var meanSampleCount: Double
        var rmsResidualM: Double
    }

    struct DisplayInfo: Codable, Equatable, Sendable {
        var preferredContourIntervalInches: Double
        var productLanguage: String
    }

    struct GPSApprox: Codable, Equatable, Sendable {
        var lat: Double?
        var lon: Double?
        var horizontalAccuracyM: Double?
    }

    struct GeorefHooks: Codable, Equatable, Sendable {
        var usGisReady: Bool
        var controlPointsCount: Int
    }

    struct GeorefInfo: Codable, Equatable, Sendable {
        var method: String
        var gpsApprox: GPSApprox
        var hooks: GeorefHooks
    }

    var schemaVersion: Int
    var scanId: String
    var projectId: String
    var capturedAt: String
    var device: DeviceInfo
    var frame: FrameInfo
    var capture: CaptureInfo
    var quality: QualityInfo
    var display: DisplayInfo
    var georef: GeorefInfo
    var disclaimer: String
}

struct ScanPackage: Sendable {
    var directory: URL
    var metadata: ScanMetadata
    var heightmapURL: URL
    var metadataURL: URL
}

enum ScanPackageWriter {
    static let disclaimer =
        "Averaged LiDAR grade for cut/fill planning. Not a certified survey."

    static func makeMetadata(
        scanId: UUID,
        projectId: UUID,
        capturedAt: Date = Date(),
        heightmap: HeightmapResult,
        metrics: QualityMetrics,
        durationSec: TimeInterval,
        minSamplesPerCell: Int,
        preferredContourIntervalInches: Double,
        controlPointsCount: Int,
        hasLiDAR: Bool
    ) -> ScanMetadata {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return ScanMetadata(
            schemaVersion: 1,
            scanId: scanId.uuidString,
            projectId: projectId.uuidString,
            capturedAt: formatter.string(from: capturedAt),
            device: .init(
                model: DeviceCapability.deviceModelIdentifier,
                osVersion: DeviceCapability.osVersionString,
                hasLiDAR: hasLiDAR
            ),
            frame: .init(
                upAxis: "y",
                units: "meters",
                origin: .init(x: heightmap.originX, y: 0, z: heightmap.originZ),
                cellSizeM: heightmap.cellSizeM,
                width: heightmap.width,
                height: heightmap.height,
                boundsMin: .init(
                    x: heightmap.bounds.minX,
                    y: heightmap.bounds.minY,
                    z: heightmap.bounds.minZ
                ),
                boundsMax: .init(
                    x: heightmap.bounds.maxX,
                    y: heightmap.bounds.maxY,
                    z: heightmap.bounds.maxZ
                ),
                rowDirection: "+Z",
                columnDirection: "+X"
            ),
            capture: .init(
                passCount: metrics.passCount,
                durationSec: durationSec,
                minSamplesPerCell: minSamplesPerCell
            ),
            quality: .init(
                qualityScore: metrics.qualityScore,
                coverageRatio: metrics.coverageRatio,
                holeRatio: metrics.holeRatio,
                meanSampleCount: metrics.meanSampleCount,
                rmsResidualM: metrics.rmsResidualM
            ),
            display: .init(
                preferredContourIntervalInches: preferredContourIntervalInches,
                productLanguage: "field_grade_volume_estimating"
            ),
            georef: .init(
                method: "none",
                gpsApprox: .init(lat: nil, lon: nil, horizontalAccuracyM: nil),
                hooks: .init(usGisReady: false, controlPointsCount: controlPointsCount)
            ),
            disclaimer: disclaimer
        )
    }

    static func writePackage(
        to directory: URL,
        metadata: ScanMetadata,
        heightmap: HeightmapResult,
        fileManager: FileManager = .default
    ) throws -> ScanPackage {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let metadataURL = directory.appendingPathComponent("metadata.json")
        let heightmapURL = directory.appendingPathComponent("heightmap.f32")
        let previewURL = directory.appendingPathComponent("heightmap.png")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metaData = try encoder.encode(metadata)
        try metaData.write(to: metadataURL, options: .atomic)

        var floats = heightmap.elevations
        let byteCount = floats.count * MemoryLayout<Float>.size
        let raw = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        precondition(raw.count == byteCount)
        try raw.write(to: heightmapURL, options: .atomic)

        if let cgImage = HeightmapPreviewImage.cgImage(from: heightmap) {
            writePNG(cgImage, to: previewURL)
        }

        return ScanPackage(
            directory: directory,
            metadata: metadata,
            heightmapURL: heightmapURL,
            metadataURL: metadataURL
        )
    }

    static func encodeMetadata(_ metadata: ScanMetadata) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(metadata)
    }

    static func decodeMetadata(from data: Data) throws -> ScanMetadata {
        try JSONDecoder().decode(ScanMetadata.self, from: data)
    }

    private static func writePNG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
