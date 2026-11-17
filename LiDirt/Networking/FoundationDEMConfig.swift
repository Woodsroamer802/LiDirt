import Foundation

/// Foundation DEM source for Job Site / Contour maps.
///
/// Public-domain USGS 3DEP via The National Map (same family of services as
/// [Lidar Explorer](https://apps.nationalmap.gov/lidar-explorer/#/)):
/// `elevation.nationalmap.gov` … `/3DEPElevation/ImageServer`.
/// No API key and no self-hosted mirror required.
enum FoundationDEMConfig {
    /// National Map 3DEP Bare Earth DEM ImageServer (getSamples / identify / exportImage).
    static let nationalMapImageServer =
        "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer"

    static var getSamplesEndpoint: String { "\(nationalMapImageServer)/getSamples" }

    /// Attribution for UI / print notes.
    static let attribution =
        "USGS 3DEP elevation (The National Map / Lidar Explorer). Public domain."
}
