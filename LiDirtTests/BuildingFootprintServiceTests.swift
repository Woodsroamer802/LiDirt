import XCTest
import CoreLocation
@testable import LiDirt

final class BuildingFootprintServiceTests: XCTestCase {
    func testDecodeOverpassWays() throws {
        let json = """
        {
          "elements": [
            {
              "type": "way",
              "id": 42,
              "tags": { "building": "house" },
              "geometry": [
                { "lat": 40.0, "lon": -105.0 },
                { "lat": 40.0, "lon": -104.999 },
                { "lat": 39.999, "lon": -104.999 },
                { "lat": 40.0, "lon": -105.0 }
              ]
            }
          ]
        }
        """
        let buildings = try BuildingFootprintService.decode(Data(json.utf8))
        XCTAssertEqual(buildings.count, 1)
        XCTAssertEqual(buildings[0].id, "way-42")
        XCTAssertEqual(buildings[0].kind, "house")
        XCTAssertGreaterThanOrEqual(buildings[0].coordinates.count, 4)
        let first = buildings[0].coordinates.first!
        let last = buildings[0].coordinates.last!
        XCTAssertEqual(first.latitude, last.latitude, accuracy: 1e-9)
        XCTAssertEqual(first.longitude, last.longitude, accuracy: 1e-9)
    }
}
