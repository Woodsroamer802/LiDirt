import Foundation

enum GISDisclaimer {
    static let topoContours =
        "USGS topo tiles are public basemap context. LiDAR contours are from your averaged phone scan, placed with phone GPS/compass (meters-class). Display / planning aid only — not a certified survey or absolute elevation."

    static let needScanGPS =
        "Scan with Location on so contours can sit on the topo map. Without a GPS fix, the map still shows USGS topo."
}
