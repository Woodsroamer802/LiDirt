import Foundation

enum GISDisclaimer {
    static let topoContours =
        "USGS topo tiles provide visual context. Elevations fuse USGS 3DEP as the foundation with your phone LiDAR DEM for pad detail (GPS/compass place, meters-class). Planning aid for heavy equipment — not a certified survey or absolute elevation."

    static let needScanGPS =
        "Scan with Location on so LiDAR can be placed and fused onto the topo/3DEP foundation. Without a GPS fix, the map still shows USGS topo."
}
