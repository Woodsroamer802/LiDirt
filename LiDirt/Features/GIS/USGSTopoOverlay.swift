import MapKit
import UIKit

/// USGS National Map topographic basemap tiles (public domain / government).
///
/// National Map topo typically tops out at z16. Past that we still accept MapKit
/// tile requests and **upscale the parent z16 tile** so zooming into a pad after
/// a scan keeps USGS topo instead of blanking or falling through to Apple maps.
enum USGSTopoOverlay {
    static let pathTemplate =
        "https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/tile/{z}/{y}/{x}"

    /// Native USGS topo max zoom (beyond this we synthesize by upscaling).
    static let nativeMaximumZ = 16
    /// Allow MapKit to request deeper zooms so pad-scale scans stay on topo.
    static let displayMaximumZ = 20
    static let tilePixelSize = 256

    static func makeOverlay() -> MKTileOverlay {
        USGSTopoTileOverlay()
    }
}

/// Tile overlay that replaces Apple map content and fills z>16 by cropping/scaling z16 parents.
final class USGSTopoTileOverlay: MKTileOverlay {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        super.init(urlTemplate: USGSTopoOverlay.pathTemplate)
        canReplaceMapContent = true
        minimumZ = 0
        maximumZ = USGSTopoOverlay.displayMaximumZ
        tileSize = CGSize(
            width: USGSTopoOverlay.tilePixelSize,
            height: USGSTopoOverlay.tilePixelSize
        )
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let z = min(path.z, USGSTopoOverlay.nativeMaximumZ)
        var x = path.x
        var y = path.y
        if path.z > USGSTopoOverlay.nativeMaximumZ {
            let diff = path.z - USGSTopoOverlay.nativeMaximumZ
            x = path.x >> diff
            y = path.y >> diff
        }
        let urlString = USGSTopoOverlay.pathTemplate
            .replacingOccurrences(of: "{z}", with: "\(z)")
            .replacingOccurrences(of: "{y}", with: "\(y)")
            .replacingOccurrences(of: "{x}", with: "\(x)")
        return URL(string: urlString)!
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let requestURL = url(forTilePath: path)
        let task = session.dataTask(with: requestURL) { data, response, error in
            if let error {
                result(nil, error)
                return
            }
            guard let data, !data.isEmpty else {
                result(nil, URLError(.badServerResponse))
                return
            }
            if path.z <= USGSTopoOverlay.nativeMaximumZ {
                result(data, nil)
                return
            }
            guard let parent = UIImage(data: data),
                  let upscaled = Self.upscaleTile(parent: parent, path: path) else {
                result(nil, URLError(.cannotDecodeContentData))
                return
            }
            result(upscaled, nil)
        }
        task.resume()
    }

    /// Crops the parent z16 tile to the child quadrant and scales to 256×256 PNG.
    static func upscaleTile(parent: UIImage, path: MKTileOverlayPath) -> Data? {
        let zoomDiff = path.z - USGSTopoOverlay.nativeMaximumZ
        guard zoomDiff > 0 else { return parent.pngData() }
        guard let cgImage = parent.cgImage else { return parent.pngData() }

        let divisions = 1 << zoomDiff
        let localX = path.x % divisions
        let localY = path.y % divisions
        let parentW = cgImage.width
        let parentH = cgImage.height
        let cropW = max(parentW / divisions, 1)
        let cropH = max(parentH / divisions, 1)
        let cropRect = CGRect(
            x: localX * cropW,
            y: localY * cropH,
            width: min(cropW, parentW - localX * cropW),
            height: min(cropH, parentH - localY * cropH)
        )
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        let outSize = CGSize(
            width: USGSTopoOverlay.tilePixelSize,
            height: USGSTopoOverlay.tilePixelSize
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outSize, format: format)
        let image = renderer.image { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: outSize))
        }
        return image.pngData()
    }
}
