import MapKit

/// USGS National Map topographic basemap tiles (public domain / government).
enum USGSTopoOverlay {
    /// ArcGIS MapServer tile path: level / row / col → z / y / x.
    static let pathTemplate =
        "https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/tile/{z}/{y}/{x}"

    static func makeOverlay() -> MKTileOverlay {
        let overlay = MKTileOverlay(urlTemplate: pathTemplate)
        overlay.canReplaceMapContent = true
        overlay.minimumZ = 0
        overlay.maximumZ = 16
        return overlay
    }
}
