import XCTest
@testable import LiDirt

final class MaterialsCalculatorTests: XCTestCase {
    func testSlabOnLimestoneQuantities() {
        // 27 ft × 10 ft = 270 ft² → 10 yd² footprint.
        // 6″ gravel = 270 × 0.5 / 27 = 5 yd³ net → ×1.15 order = 5.75
        // 4″ concrete = 270 × (4/12) / 27 = 3.333… → ×1.05 ≈ 3.5
        let cutout = GradeCutout(
            label: "Concrete slab",
            shape: .rectangle,
            mode: .setAbsoluteElevation,
            widthFeet: 27,
            lengthFeet: 10,
            depthFeet: 10.0 / 12.0,
            centerLocalX: 0,
            centerLocalZ: 0
        )
        let dem = ProposedGradeVolume(cutCubicYards: 4, fillCubicYards: 0, cellsEdited: 20)
        let estimate = MaterialsCalculator.estimate(
            cutouts: [cutout],
            assembliesByCutoutId: [cutout.id: .slabOnLimestone2],
            demVolume: dem
        )

        XCTAssertEqual(estimate.footprintAreaSquareFeet, 270, accuracy: 0.01)

        let gravel = estimate.lineItems.first { $0.material == .limestone2 }
        XCTAssertNotNil(gravel)
        XCTAssertEqual(gravel!.quantity, 5 * 1.15, accuracy: 0.05)
        XCTAssertNotNil(gravel!.secondaryQuantity)

        let concrete = estimate.lineItems.first { $0.material == .concrete }
        XCTAssertNotNil(concrete)
        let expectedConcrete = MaterialsCalculator.volumeCubicYards(
            areaSquareFeet: 270,
            thicknessFeet: 4.0 / 12.0
        ) * MaterialKind.concrete.orderFactor
        XCTAssertEqual(concrete!.quantity, expectedConcrete, accuracy: 0.05)

        let dirt = estimate.lineItems.first { $0.material == .excavatedDirt }
        XCTAssertNotNil(dirt)
        // Assembly dig 10″ over 270 ft² = 270 * (10/12) / 27 = 8.333 yd³ > DEM cut 4
        XCTAssertEqual(dirt!.quantity, 270 * (10.0 / 12.0) / 27.0, accuracy: 0.05)
    }

    func testCirclePoolDirtFromDepth() {
        let pool = GradeCutout(
            label: "Swimming pool",
            shape: .circle,
            mode: .digBelowSurface,
            widthFeet: 20, // diameter
            lengthFeet: 20,
            depthFeet: 5,
            centerLocalX: 0,
            centerLocalZ: 0
        )
        let area = pool.footprintAreaSquareFeet
        XCTAssertEqual(area, .pi * 100, accuracy: 0.01)

        let estimate = MaterialsCalculator.estimate(
            cutouts: [pool],
            assembliesByCutoutId: [pool.id: .poolDirtOnly],
            demVolume: ProposedGradeVolume(cutCubicYards: 0, fillCubicYards: 0, cellsEdited: 0)
        )
        let dirt = estimate.lineItems.first { $0.material == .excavatedDirt }
        XCTAssertNotNil(dirt)
        let expected = MaterialsCalculator.volumeCubicYards(areaSquareFeet: area, thicknessFeet: 5)
        XCTAssertEqual(dirt!.quantity, expected, accuracy: 0.05)
        XCTAssertNil(estimate.lineItems.first { $0.material == .concrete })
    }

    func testVolumeHelper() {
        // 27 ft² × 1 ft = 1 yd³
        XCTAssertEqual(
            MaterialsCalculator.volumeCubicYards(areaSquareFeet: 27, thicknessFeet: 1),
            1,
            accuracy: 1e-9
        )
    }

    func testRegionalPriceQuoteOnSlab() {
        let cutout = GradeCutout(
            label: "Concrete slab",
            shape: .rectangle,
            mode: .setAbsoluteElevation,
            widthFeet: 27,
            lengthFeet: 10,
            depthFeet: 10.0 / 12.0,
            centerLocalX: 0,
            centerLocalZ: 0
        )
        let estimate = MaterialsCalculator.estimate(
            cutouts: [cutout],
            assembliesByCutoutId: [cutout.id: .slabOnLimestone2],
            demVolume: ProposedGradeVolume(cutCubicYards: 4, fillCubicYards: 0, cellsEdited: 20),
            priceCatalog: .ohioPennsylvaniaWestVirginia
        )

        let gravel = estimate.lineItems.first { $0.material == .limestone2 }
        XCTAssertNotNil(gravel?.priceQuote)
        XCTAssertEqual(gravel!.priceQuote!.catalogId, "agg-57-2b")
        // 5.75 yd³ × 1.45 t/yd³ × $45/ton
        let expectedTons = 5.75 * 1.45
        XCTAssertEqual(gravel!.priceQuote!.billableQuantity, expectedTons, accuracy: 0.05)
        XCTAssertEqual(gravel!.priceQuote!.extendedAvg, expectedTons * 45, accuracy: 1)

        let concrete = estimate.lineItems.first { $0.material == .concrete }
        XCTAssertNotNil(concrete?.priceQuote)
        XCTAssertEqual(concrete!.priceQuote!.catalogId, "conc-readymix-4000")
        XCTAssertNotNil(estimate.estimatedMaterialCostAvg)
        XCTAssertGreaterThan(estimate.estimatedMaterialCostAvg!, 0)
    }

    func testPriceCatalogHasExpectedCategories() {
        let catalog = RegionalPriceCatalog.ohioPennsylvaniaWestVirginia
        XCTAssertEqual(catalog.materials.count, 25)
        XCTAssertTrue(catalog.categories.contains("Aggregates & Earthwork"))
        XCTAssertTrue(catalog.categories.contains("Septic System Components"))
        XCTAssertNotNil(catalog.item(id: "septic-riser-lid"))
        XCTAssertEqual(catalog.item(id: "agg-57-2b")?.priceAvg, 45, accuracy: 0.01)
    }
}
