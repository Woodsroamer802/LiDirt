import Foundation

enum GISDisclaimer {
    static let trespass =
        "Boundary lines are for awareness only — to help avoid accidental trespass. They are not a survey, title search, or legal property determination. Confirm ownership and permission before entering land."

    static let dataLimits =
        "USGS topo tiles are public. Parcel lines come from the configured open government / county GIS source (or none if unset). Coverage and accuracy vary widely by county. Phone GPS is meters-class."

    /// Clarifies that LiDirt does not include a built-in nationwide parcel database.
    static let noNationwideParcels =
        "LiDirt does not include a nationwide private-parcel database. Add your county’s public parcel FeatureServer or GeoJSON in Settings for local boundary lines."
}
