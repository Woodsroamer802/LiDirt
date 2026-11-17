import Foundation

enum GISDisclaimer {
    static let topoContours =
        "Job Site map is built from USGS 3DEP elevation (The National Map / Lidar Explorer, public domain) + phone LiDAR, placed with GPS (meters-class). Hillshade/contours are our Contour map — not a certified survey or absolute elevation."

    static let needScanGPS =
        "Scan with Location on so LiDAR can be placed on the topo/3DEP foundation for the Contour map. Without a GPS fix, the map still shows USGS topo."
}
