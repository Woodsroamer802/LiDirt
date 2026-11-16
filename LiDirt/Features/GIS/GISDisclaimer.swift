import Foundation

enum GISDisclaimer {
    static let topoContours =
        "Job Site map is built from USGS 3DEP elevation + phone LiDAR, placed with GPS (meters-class). Hillshade/contours are our fused surface — not a certified survey or absolute elevation."

    static let needScanGPS =
        "Scan with Location on so LiDAR can be placed and fused onto the topo/3DEP foundation. Without a GPS fix, the map still shows USGS topo."
}
