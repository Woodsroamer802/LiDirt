import MapKit
import UIKit

/// Georeferenced fused elevation map (3DEP + LiDAR + GPS) drawn as a single image overlay.
final class FusedMapGroundOverlay: NSObject, MKOverlay {
    let image: UIImage
    let siteBounds: JobSiteBounds

    var coordinate: CLLocationCoordinate2D { siteBounds.center }
    var boundingMapRect: MKMapRect { siteBounds.mapRect }

    init(image: UIImage, bounds: JobSiteBounds) {
        self.image = image
        self.siteBounds = bounds
        super.init()
    }
}

/// Draws the fused map image into the overlay’s map rect.
///
/// Uses the ObjC `drawMapRect:zoomScale:` selector explicitly. Some Swift/MapKit
/// SDK views don’t surface `draw(_:zoomScale:)` as an overridable Swift method
/// (“Method does not override any method from its superclass”).
final class FusedMapOverlayRenderer: MKOverlayRenderer {
    @objc(drawMapRect:zoomScale:)
    func drawMapRect(_ mapRect: MKMapRect, zoomScale: MKZoomScale) {
        guard let fused = overlay as? FusedMapGroundOverlay,
              let cgImage = fused.image.cgImage,
              let context = UIGraphicsGetCurrentContext() else { return }

        let imageRect = rect(for: fused.boundingMapRect)
        let tileRect = rect(for: mapRect)
        guard imageRect.intersects(tileRect) else { return }

        context.saveGState()
        // CGContext is flipped vs UIKit image orientation.
        context.translateBy(x: imageRect.minX, y: imageRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(origin: .zero, size: imageRect.size))
        context.restoreGState()
    }

    @objc(canDrawMapRect:zoomScale:)
    func canDrawMapRect(_ mapRect: MKMapRect, zoomScale: MKZoomScale) -> Bool {
        overlay is FusedMapGroundOverlay
    }
}
