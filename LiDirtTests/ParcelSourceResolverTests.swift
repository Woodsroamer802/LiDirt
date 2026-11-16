import XCTest
@testable import LiDirt

final class ParcelSourceResolverTests: XCTestCase {
    func testNormalizeStateAbbreviations() {
        XCTAssertEqual(ApplePlaceLookup.normalizeState("tx"), "TX")
        XCTAssertEqual(ApplePlaceLookup.normalizeState("Texas"), "TX")
        XCTAssertEqual(ApplePlaceLookup.normalizeState("washington"), "WA")
    }

    func testLayerURLAppendsDefaultIndex() {
        XCTAssertEqual(
            ParcelSourceResolver.layerURLAppendingDefaultIndex(
                "https://example.com/arcgis/rest/services/Parcels/FeatureServer"
            ),
            "https://example.com/arcgis/rest/services/Parcels/FeatureServer/0"
        )
        XCTAssertEqual(
            ParcelSourceResolver.layerURLAppendingDefaultIndex(
                "https://example.com/arcgis/rest/services/Parcels/FeatureServer/3"
            ),
            "https://example.com/arcgis/rest/services/Parcels/FeatureServer/3"
        )
    }

    func testPickBestPrefersParcelTitleWithCounty() {
        let hits: [ParcelSourceResolver.SearchHit] = [
            .init(title: "Roads AZ", url: "https://example.com/FeatureServer", type: "Feature Service"),
            .init(
                title: "Maricopa County Parcels",
                url: "https://example.com/Parcels/FeatureServer",
                type: "Feature Service"
            ),
            .init(title: "Zoning", url: "https://example.com/Zoning/FeatureServer", type: "Feature Service")
        ]
        let best = ParcelSourceResolver.pickBest(candidates: hits, county: "Maricopa", state: "AZ")
        XCTAssertEqual(best?.title, "Maricopa County Parcels")
    }

    func testDecodeArcGISSearchResults() throws {
        let json = """
        {
          "results": [
            {
              "title": "Sample County Parcels",
              "url": "https://services.arcgis.com/demo/arcgis/rest/services/Parcels/FeatureServer",
              "type": "Feature Service"
            }
          ]
        }
        """
        let hits = try ParcelSourceResolver.decodeSearchResults(Data(json.utf8))
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].title, "Sample County Parcels")
    }
}
