import Foundation

enum GISDisclaimer {
    static let trespass =
        "Boundary lines are for awareness only — to help avoid accidental trespass. They are not a survey, title search, or legal property determination. Confirm ownership and permission before entering land."

    static let dataLimits =
        "USGS topo tiles are public. Parcel lines come from the configured open government / county GIS source (or none if unset). Coverage and accuracy vary widely by county. Phone GPS is meters-class."

    static let notOnX =
        "LiDirt is not OnX and does not ship a licensed nationwide private-parcel database. Plug in your county’s public parcel FeatureServer or GeoJSON for local boundaries."
}
