import Foundation
import CoreLocation
import MapKit
import UIKit

struct JobSiteOfflineMeta: Codable, Equatable, Sendable {
    var projectId: String
    var projectName: String
    var savedAt: Date
    var bounds: JobSiteBounds
    var imageWidthPx: Int
    var imageHeightPx: Int
    var contourIntervalInches: Double
    var surfaceMode: String
    var contourSegmentCount: Int
    /// Long edge target pixels for zoomable phone viewing without heavy blur.
    var captureScale: Double
}

enum JobSiteOfflineError: LocalizedError {
    case noJobSite
    case snapshotFailed
    case writeFailed
    case addressNotFound

    var errorDescription: String? {
        switch self {
        case .noJobSite: return "Set a Job Site rectangle before saving offline."
        case .snapshotFailed: return "Could not capture the Job Site map snapshot."
        case .writeFailed: return "Could not write the offline Job Site image."
        case .addressNotFound: return "Could not find that address. Try a fuller street address."
        }
    }
}

/// Saves a high-resolution Job Site map image (topo snapshot + contours) for offline pan/zoom/rotate.
final class JobSiteOfflineStore: Sendable {
    /// Long edge of the offline image (~3× phone width class for modest pinch-zoom).
    static let longEdgePixels: CGFloat = 3072

    private let paths: FilePaths

    init(paths: FilePaths = .shared) {
        self.paths = paths
    }

    func packageDirectory(projectId: UUID) -> URL {
        paths.jobSiteDirectory(projectId: projectId)
    }

    func imageURL(projectId: UUID) -> URL {
        packageDirectory(projectId: projectId).appendingPathComponent("jobsite.png")
    }

    func metaURL(projectId: UUID) -> URL {
        packageDirectory(projectId: projectId).appendingPathComponent("meta.json")
    }

    func hasPackage(projectId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: imageURL(projectId: projectId).path)
            && FileManager.default.fileExists(atPath: metaURL(projectId: projectId).path)
    }

    func loadMeta(projectId: UUID) -> JobSiteOfflineMeta? {
        guard let data = try? Data(contentsOf: metaURL(projectId: projectId)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(JobSiteOfflineMeta.self, from: data)
    }

    func loadImage(projectId: UUID) -> UIImage? {
        guard let data = try? Data(contentsOf: imageURL(projectId: projectId)) else { return nil }
        return UIImage(data: data)
    }

    func deletePackage(projectId: UUID) {
        try? FileManager.default.removeItem(at: packageDirectory(projectId: projectId))
    }

    @MainActor
    func save(
        projectId: UUID,
        projectName: String,
        bounds: JobSiteBounds,
        contourPolylines: [ContourMapGeoref.ContourPolyline],
        contourIntervalInches: Double,
        surfaceMode: ContourSurfaceMode,
        heightmap: HeightmapResult? = nil,
        origin: CLLocationCoordinate2D? = nil,
        progress: ((String) -> Void)? = nil
    ) async throws -> JobSiteOfflineMeta {
        guard bounds.isValid else { throw JobSiteOfflineError.noJobSite }

        let composed: UIImage
        if let heightmap, let origin,
           let rendered = FusedSiteMapRenderer.render(
            heightmap: heightmap,
            origin: origin,
            bounds: bounds,
            intervalInches: contourIntervalInches,
            drawContours: true,
            longEdge: Self.longEdgePixels
           ),
           let fusedImage = rendered.image {
            progress?("Rendering fused 3DEP + LiDAR map…")
            composed = fusedImage
        } else {
            progress?("Capturing high-res Job Site snapshot…")
            let size = Self.snapshotPixelSize(for: bounds)
            let snapshot = try await captureTopoSnapshot(bounds: bounds, size: size)
            progress?("Drawing contours on snapshot…")
            composed = Self.compose(
                snapshot: snapshot,
                bounds: bounds,
                contours: contourPolylines
            )
        }
        guard let png = composed.pngData() else { throw JobSiteOfflineError.writeFailed }

        let dir = packageDirectory(projectId: projectId)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: imageURL(projectId: projectId), options: .atomic)

        let meta = JobSiteOfflineMeta(
            projectId: projectId.uuidString,
            projectName: projectName,
            savedAt: Date(),
            bounds: bounds,
            imageWidthPx: Int(composed.size.width * composed.scale),
            imageHeightPx: Int(composed.size.height * composed.scale),
            contourIntervalInches: contourIntervalInches,
            surfaceMode: surfaceMode.rawValue,
            contourSegmentCount: contourPolylines.count,
            captureScale: Double(Self.longEdgePixels)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(meta).write(to: metaURL(projectId: projectId), options: .atomic)
        progress?("Job Site saved offline.")
        return meta
    }

    static func snapshotPixelSize(for bounds: JobSiteBounds) -> CGSize {
        let aspect = max(bounds.longitudeDelta, 1e-9) / max(bounds.latitudeDelta, 1e-9)
        if aspect >= 1 {
            return CGSize(width: longEdgePixels, height: max(longEdgePixels / aspect, 512))
        }
        return CGSize(width: max(longEdgePixels * aspect, 512), height: longEdgePixels)
    }

    @MainActor
    private func captureTopoSnapshot(bounds: JobSiteBounds, size: CGSize) async throws -> MKMapSnapshotter.Snapshot {
        let options = MKMapSnapshotter.Options()
        options.region = bounds.region
        options.size = size
        options.scale = 1
        options.mapType = .standard
        // Prefer imagery-free topo-like look; snapshotter can't use custom tile overlays,
        // so we use muted standard + later contour draw. Satellite hybrid is too busy for grade work.
        if #available(iOS 17.0, *) {
            options.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        }
        let snapshotter = MKMapSnapshotter(options: options)
        do {
            return try await snapshotter.start()
        } catch {
            throw JobSiteOfflineError.snapshotFailed
        }
    }

    static func compose(
        snapshot: MKMapSnapshotter.Snapshot,
        bounds: JobSiteBounds,
        contours: [ContourMapGeoref.ContourPolyline]
    ) -> UIImage {
        let image = snapshot.image
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { ctx in
            image.draw(at: .zero)
            let cg = ctx.cgContext

            // Job Site frame
            let corners = bounds.cornerCoordinates.map { snapshot.point(for: $0) }
            if corners.count == 4 {
                cg.setStrokeColor(UIColor(red: 0.96, green: 0.78, blue: 0.12, alpha: 1).cgColor)
                cg.setLineWidth(3)
                cg.setLineDash(phase: 0, lengths: [10, 6])
                cg.move(to: corners[0])
                for p in corners.dropFirst() { cg.addLine(to: p) }
                cg.closePath()
                cg.strokePath()
                cg.setLineDash(phase: 0, lengths: [])
            }

            // Contours
            cg.setStrokeColor(UIColor(red: 0.85, green: 0.55, blue: 0.05, alpha: 1).cgColor)
            cg.setLineWidth(1.4)
            for line in contours {
                guard line.coordinates.count >= 2 else { continue }
                let a = snapshot.point(for: line.coordinates[0])
                let b = snapshot.point(for: line.coordinates[1])
                // Skip segments far outside the image.
                if (a.x < -20 && b.x < -20) || (a.y < -20 && b.y < -20) { continue }
                if (a.x > image.size.width + 20 && b.x > image.size.width + 20) { continue }
                if (a.y > image.size.height + 20 && b.y > image.size.height + 20) { continue }
                cg.move(to: a)
                cg.addLine(to: b)
                cg.strokePath()
            }

            // Title strip
            let banner = CGRect(x: 0, y: 0, width: image.size.width, height: 36)
            UIColor(white: 0.12, alpha: 0.72).setFill()
            cg.fill(banner)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            ("LiDirt Job Site — offline map" as NSString).draw(
                at: CGPoint(x: 12, y: 10),
                withAttributes: attrs
            )
        }
    }
}
