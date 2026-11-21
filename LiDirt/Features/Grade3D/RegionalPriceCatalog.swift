import Foundation

/// Sale unit shown in the Price Book.
enum PriceCatalogUnit: String, Codable, CaseIterable, Sendable {
    case ton
    case cubicYard
    case stick
    case sheet
    case roll
    case piece
    case linearFoot
    case each
    case set

    var displayName: String {
        switch self {
        case .ton: return "ton"
        case .cubicYard: return "cubic yard"
        case .stick: return "stick"
        case .sheet: return "sheet"
        case .roll: return "roll"
        case .piece: return "piece"
        case .linearFoot: return "linear foot"
        case .each: return "each"
        case .set: return "set"
        }
    }
}

struct PriceCatalogItem: Identifiable, Equatable, Sendable {
    var id: String
    var category: String
    var name: String
    var unit: PriceCatalogUnit
    var priceMin: Double
    var priceMax: Double
    var priceAvg: Double

    var lineSummary: String {
        String(
            format: "$%.2f/%@ avg ($%.2f – $%.2f)",
            priceAvg,
            unit.displayName,
            priceMin,
            priceMax
        )
    }
}

struct MaterialPriceQuote: Equatable, Sendable {
    var catalogId: String
    var catalogName: String
    var unit: PriceCatalogUnit
    var billableQuantity: Double
    var extendedMin: Double
    var extendedMax: Double
    var extendedAvg: Double

    var rangeSummary: String {
        String(format: "$%.0f–$%.0f (avg $%.0f)", extendedMin, extendedMax, extendedAvg)
    }
}

/// OH / PA / WV yard rates used by the Price Book and materials estimates.
struct RegionalPriceCatalog: Equatable, Sendable {
    var region: String
    var materials: [PriceCatalogItem]

    func item(id: String) -> PriceCatalogItem? {
        materials.first { $0.id == id }
    }

    var categories: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for material in materials where seen.insert(material.category).inserted {
            ordered.append(material.category)
        }
        return ordered
    }

    func materials(in category: String) -> [PriceCatalogItem] {
        materials.filter { $0.category == category }
    }

    func quote(itemId: String, quantity: Double) -> MaterialPriceQuote? {
        guard let item = item(id: itemId), quantity > 1e-9 else { return nil }
        return MaterialPriceQuote(
            catalogId: item.id,
            catalogName: item.name,
            unit: item.unit,
            billableQuantity: quantity,
            extendedMin: quantity * item.priceMin,
            extendedMax: quantity * item.priceMax,
            extendedAvg: quantity * item.priceAvg
        )
    }

    static var `default`: RegionalPriceCatalog { .ohioPennsylvaniaWestVirginia }

    /// Cambridge / Youngstown / Pittsburgh / Moundsville yard pickup averages.
    static let ohioPennsylvaniaWestVirginia = RegionalPriceCatalog(
        region: "Cambridge, OH · Youngstown, OH · Pittsburgh, PA · Moundsville, WV",
        materials: [
            // Aggregates & Earthwork
            .init(id: "agg-57-2b", category: "Aggregates & Earthwork",
                  name: "#57 / 2B Crushed Limestone (3/4\"–1\" Clean)",
                  unit: .ton, priceMin: 38, priceMax: 52, priceAvg: 45),
            .init(id: "agg-2a-304", category: "Aggregates & Earthwork",
                  name: "2A Modified / #304 / #411 Crusher Run",
                  unit: .ton, priceMin: 32, priceMax: 46, priceAvg: 39),
            .init(id: "agg-3-4-surge", category: "Aggregates & Earthwork",
                  name: "#3 or #4 Limestone (1.5\"–3\" Surge/Ballast)",
                  unit: .ton, priceMin: 40, priceMax: 52, priceAvg: 46),
            .init(id: "agg-mason-sand", category: "Aggregates & Earthwork",
                  name: "Mason / Pool Sand & Concrete Sand",
                  unit: .ton, priceMin: 42, priceMax: 60, priceAvg: 51),
            .init(id: "agg-slag", category: "Aggregates & Earthwork",
                  name: "Air-Cooled Blast Furnace Slag",
                  unit: .ton, priceMin: 22, priceMax: 35, priceAvg: 28.50),
            .init(id: "earth-fill-dirt", category: "Aggregates & Earthwork",
                  name: "Clean Fill Dirt / Clay Fill",
                  unit: .cubicYard, priceMin: 10, priceMax: 20, priceAvg: 15),
            .init(id: "earth-topsoil", category: "Aggregates & Earthwork",
                  name: "Screened Topsoil",
                  unit: .cubicYard, priceMin: 28, priceMax: 45, priceAvg: 36.50),

            // Concrete & Reinforcement
            .init(id: "conc-readymix-4000", category: "Concrete & Reinforcement",
                  name: "Ready-Mix Concrete (3,500–4,000 PSI, Air-Entrained)",
                  unit: .cubicYard, priceMin: 130, priceMax: 165, priceAvg: 147.50),
            .init(id: "conc-rebar-4", category: "Concrete & Reinforcement",
                  name: "#4 Rebar (1/2\" × 20′ Stick)",
                  unit: .stick, priceMin: 11, priceMax: 15, priceAvg: 13),
            .init(id: "conc-wire-mesh", category: "Concrete & Reinforcement",
                  name: "6×6 Welded Wire Mesh (8′×20′ Sheet)",
                  unit: .sheet, priceMin: 30, priceMax: 65, priceAvg: 47.50),
            .init(id: "conc-vapor-barrier", category: "Concrete & Reinforcement",
                  name: "Vapor Barrier (6-mil to 10-mil Poly, 20′×100′ Roll)",
                  unit: .roll, priceMin: 75, priceMax: 140, priceAvg: 107.50),
            .init(id: "conc-expansion-joint", category: "Concrete & Reinforcement",
                  name: "Expansion Joint Strip (10′ Length)",
                  unit: .piece, priceMin: 8, priceMax: 14, priceAvg: 11),

            // Drainage & Geotextiles
            .init(id: "drain-perf-hdpe", category: "Drainage & Geotextiles",
                  name: "4\" Perforated Corrugated HDPE Pipe (100′ Roll)",
                  unit: .roll, priceMin: 70, priceMax: 125, priceAvg: 97.50),
            .init(id: "drain-solid-pvc", category: "Drainage & Geotextiles",
                  name: "4\" Solid SDR-35 / Schedule 40 PVC Pipe",
                  unit: .linearFoot, priceMin: 1.80, priceMax: 3.20, priceAvg: 2.50),
            .init(id: "geo-nonwoven-filter", category: "Drainage & Geotextiles",
                  name: "Non-Woven Geotextile Filter Fabric (4–6 oz)",
                  unit: .roll, priceMin: 180, priceMax: 320, priceAvg: 250),
            .init(id: "geo-woven-stabilization", category: "Drainage & Geotextiles",
                  name: "Woven Stabilization Geotextile Fabric",
                  unit: .roll, priceMin: 350, priceMax: 550, priceAvg: 450),
            .init(id: "drain-basins-emitters", category: "Drainage & Geotextiles",
                  name: "Catch Basins & Pop-Up Emitters",
                  unit: .each, priceMin: 15, priceMax: 45, priceAvg: 30),
            .init(id: "drain-pvc-fittings", category: "Drainage & Geotextiles",
                  name: "4\" PVC Drainage Fittings (Wyes, Elbows, Couplers)",
                  unit: .each, priceMin: 4, priceMax: 12, priceAvg: 8),
            .init(id: "erosion-silt-fence", category: "Drainage & Geotextiles",
                  name: "Silt Fence (3′ × 100′ with Wooden Stakes)",
                  unit: .roll, priceMin: 35, priceMax: 55, priceAvg: 45),

            // Septic System Components
            .init(id: "septic-tank-1000-conc", category: "Septic System Components",
                  name: "1,000-Gallon Precast Concrete Septic Tank",
                  unit: .each, priceMin: 950, priceMax: 1500, priceAvg: 1225),
            .init(id: "septic-tank-1000-poly", category: "Septic System Components",
                  name: "1,000-Gallon Polyethylene Septic Tank",
                  unit: .each, priceMin: 1400, priceMax: 2300, priceAvg: 1850),
            .init(id: "septic-tank-1500", category: "Septic System Components",
                  name: "1,500-Gallon Septic Tank (Concrete or Poly)",
                  unit: .each, priceMin: 1600, priceMax: 3200, priceAvg: 2400),
            .init(id: "septic-leach-chambers", category: "Septic System Components",
                  name: "Plastic Leaching Chambers (4′ Section)",
                  unit: .each, priceMin: 30, priceMax: 45, priceAvg: 37.50),
            .init(id: "septic-dbox", category: "Septic System Components",
                  name: "Distribution Box (Concrete or Poly)",
                  unit: .each, priceMin: 90, priceMax: 180, priceAvg: 135),
            .init(id: "septic-riser-lid", category: "Septic System Components",
                  name: "Septic Tank Riser & Lid Assembly (20\"–24\")",
                  unit: .each, priceMin: 75, priceMax: 150, priceAvg: 112.50),
            .init(id: "septic-effluent-filter", category: "Septic System Components",
                  name: "Effluent Filter & Sanitary Baffle Tees",
                  unit: .set, priceMin: 45, priceMax: 95, priceAvg: 70)
        ]
    )
}

extension MaterialKind {
    /// Price Book id used when estimating material cost for this kind.
    var priceCatalogId: String? {
        switch self {
        case .limestone2: return "agg-57-2b"
        case .bankRunGravel: return "agg-2a-304"
        case .sand: return "agg-mason-sand"
        case .concrete: return "conc-readymix-4000"
        case .excavatedDirt: return nil
        }
    }

    func billableCatalogQuantity(
        cubicYards: Double,
        tons: Double?,
        catalogUnit: PriceCatalogUnit
    ) -> Double? {
        switch catalogUnit {
        case .ton:
            if let tons { return tons }
            if let tpy = tonsPerCubicYard { return cubicYards * tpy }
            return nil
        case .cubicYard:
            return cubicYards
        default:
            return nil
        }
    }
}
