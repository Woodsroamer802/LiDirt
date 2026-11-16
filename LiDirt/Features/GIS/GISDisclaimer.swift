import Foundation

enum GISDisclaimer {
    static let trespass =
        "Boundary lines are for awareness only — to help avoid accidental trespass. They are not a survey, title search, or legal property determination. Confirm ownership and permission before entering land."

    static let dataLimits =
        "USGS topo tiles are public. Parcel lines come from open government / county GIS layers found by county, state, or ZIP search (or a custom URL). Coverage and accuracy vary widely by county. Phone GPS is meters-class."

    /// Clarifies that LiDirt does not include a built-in nationwide parcel database.
    static let noNationwideParcels =
        "LiDirt does not include a nationwide private-parcel database. Search by county/state or ZIP in Settings to find a public county GIS layer when one is published."
}
