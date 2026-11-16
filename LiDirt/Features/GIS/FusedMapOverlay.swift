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

final class FusedMapOverlayRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale) {
        guard let overlay = overlay as? FusedMapGroundOverlay else { return }
        let rect = self.rect(for: overlay.boundingMapRect)
        overlay.image.draw(in: rect)
    }
}
