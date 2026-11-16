import XCTest
import CoreLocation
import MapKit
@testable import LiDirt

final class ParcelBoundaryServiceTests: XCTestCase {
    func testDecodeGeoJSONPolygon() async throws {
        let geoJSON = """
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "properties": { "OWNER": "Smith" },
              "geometry": {
                "type": "Polygon",
                "coordinates": [[
                  [-97.0, 30.0],
                  [-96.9, 30.0],
                  [-96.9, 30.1],
                  [-97.0, 30.1],
                  [-97.0, 30.0]
                ]]
              }
            }
          ]
        }
        """
        let data = Data(geoJSON.utf8)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-parcels.geojson")
        try data.write(to: file)

        let service = ParcelBoundaryService()
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30.05, longitude: -96.95),
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )
        let polygons = try await service.fetchParcels(
            sourceURLString: file.absoluteString,
            region: region
        )
        XCTAssertEqual(polygons.count, 1)
        XCTAssertEqual(polygons[0].label, "Smith")
        XCTAssertGreaterThanOrEqual(polygons[0].coordinates.count, 4)
    }
}
