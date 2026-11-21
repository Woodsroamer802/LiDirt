import Foundation

/// Sale unit for a regional price-book line.
enum PriceCatalogUnit: String, Codable, CaseIterable, Sendable {
    case ton
    case cubicYard = "cubic_yard"
    case stick20ft = "stick_20ft"
    case sheet8x20 = "sheet_8x20"
    case roll2000sqft = "roll_2000sqft"
    case piece10ft = "piece_10ft"
    case roll100ft = "roll_100ft"
    case linearFoot = "linear_foot"
    case roll
    case each
    case each4ft = "each_4ft"

    var displayName: String {
        switch self {
        case .ton: return "ton"
        case .cubicYard: return "yd³"
        case .stick20ft: return "20′ stick"
        case .sheet8x20: return "8×20 sheet"
        case .roll2000sqft: return "roll (~2,000 ft²)"
        case .piece10ft: return "10′ piece"
        case .roll100ft: return "100′ roll"
        case .linearFoot: return "lf"
        case .roll: return "roll"
        case .each: return "each"
        case .each4ft: return "4′ section"
        }
    }
}

struct PriceCatalogNotes: Codable, Equatable, Sendable {
    var deliveryFees: String
    var concreteShortLoad: String
    var regionalNaming: String

    enum CodingKeys: String, CodingKey {
        case deliveryFees = "delivery_fees"
        case concreteShortLoad = "concrete_short_load"
        case regionalNaming = "regional_naming"
    }
}

struct PriceCatalogItem: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var category: String
    var name: String
    var aliases: [String]
    var unit: PriceCatalogUnit
    var conversionNote: String?
    var priceMin: Double
    var priceMax: Double
    var priceAvg: Double
    var jobTypes: [String]

    enum CodingKeys: String, CodingKey {
        case id, category, name, aliases, unit
        case conversionNote = "conversion_note"
        case priceMin = "price_min"
        case priceMax = "price_max"
        case priceAvg = "price_avg"
        case jobTypes = "job_types"
    }

    var priceRangeSummary: String {
        String(format: "$%.0f–$%.0f / %@", priceMin, priceMax, unit.displayName)
    }

    var avgSummary: String {
        String(format: "avg $%.2f / %@", priceAvg, unit.displayName)
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

/// Regional material Price Book (OH / PA / WV yard rates).
struct RegionalPriceCatalog: Codable, Equatable, Sendable {
    var region: String
    var currency: String
    var notes: PriceCatalogNotes
    var materials: [PriceCatalogItem]

    func item(id: String) -> PriceCatalogItem? {
        materials.first { $0.id == id }
    }

    var categories: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for material in materials {
            if seen.insert(material.category).inserted {
                ordered.append(material.category)
            }
        }
        return ordered
    }

    func materials(in category: String) -> [PriceCatalogItem] {
        materials.filter { $0.category == category }
    }

    /// Quote extended cost for a billable quantity in the catalog unit.
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

    /// Cambridge / Youngstown / Pittsburgh / Moundsville yard pickup rates (USD).
    static let ohioPennsylvaniaWestVirginia = RegionalPriceCatalog(
        region: "Cambridge, OH - Youngstown, OH - Pittsburgh, PA - Moundsville, WV",
        currency: "USD",
        notes: PriceCatalogNotes(
            deliveryFees: "Aggregate prices reflect yard pickup; add $75–$150 per truckload for local delivery.",
            concreteShortLoad: "Ready-mix deliveries under 7–9 cubic yards typically incur a $50–$150 short-load fee.",
            regionalNaming: "PA uses PennDOT designations (2A, 2B); OH and WV use ODOT/WVDOH designations (#304, #411, #57)."
        ),
        materials: [
            PriceCatalogItem(
                id: "agg-57-2b",
                category: "Aggregates & Earthwork",
                name: "#57 / 2B Crushed Limestone (3/4\"–1\" Clean)",
                aliases: ["OH #57", "WV #57", "PA 2B", "Clean Gravel", "#2 limestone"],
                unit: .ton,
                conversionNote: "~1.4 to 1.5 tons per cubic yard",
                priceMin: 38, priceMax: 52, priceAvg: 45,
                jobTypes: ["french_drains", "septic_systems", "basements", "concrete_pads", "swimming_pools"]
            ),
            PriceCatalogItem(
                id: "agg-2a-304",
                category: "Aggregates & Earthwork",
                name: "2A Modified / #304 / #411 Crusher Run",
                aliases: ["PA 2A", "OH #304", "OH #411", "Crusher Run", "Driveway Base"],
                unit: .ton,
                conversionNote: "~1.4 to 1.5 tons per cubic yard",
                priceMin: 32, priceMax: 46, priceAvg: 39,
                jobTypes: ["driveways", "concrete_pads", "basements", "swimming_pools"]
            ),
            PriceCatalogItem(
                id: "agg-3-4-surge",
                category: "Aggregates & Earthwork",
                name: "#3 or #4 Limestone (1.5\"–3\" Surge/Ballast)",
                aliases: ["OH #3", "OH #4", "PA #3", "Surge Stone", "Construction Entrance Stone"],
                unit: .ton,
                conversionNote: nil,
                priceMin: 40, priceMax: 52, priceAvg: 46,
                jobTypes: ["driveways", "basements", "site_prep"]
            ),
            PriceCatalogItem(
                id: "agg-mason-sand",
                category: "Aggregates & Earthwork",
                name: "Mason / Pool Sand & Concrete Sand",
                aliases: ["Pool Bottom Sand", "Pipe Bedding Sand", "Washed Sand"],
                unit: .ton,
                conversionNote: nil,
                priceMin: 42, priceMax: 60, priceAvg: 51,
                jobTypes: ["swimming_pools", "septic_systems", "concrete_pads"]
            ),
            PriceCatalogItem(
                id: "agg-slag",
                category: "Aggregates & Earthwork",
                name: "Air-Cooled Blast Furnace Slag",
                aliases: ["Crushed Slag", "Slag Base"],
                unit: .ton,
                conversionNote: nil,
                priceMin: 22, priceMax: 35, priceAvg: 28.50,
                jobTypes: ["driveways"]
            ),
            PriceCatalogItem(
                id: "earth-fill-dirt",
                category: "Aggregates & Earthwork",
                name: "Clean Fill Dirt / Clay Fill",
                aliases: ["Structural Fill", "Clean Fill"],
                unit: .cubicYard,
                conversionNote: nil,
                priceMin: 10, priceMax: 20, priceAvg: 15,
                jobTypes: ["basements", "swimming_pools", "site_prep"]
            ),
            PriceCatalogItem(
                id: "earth-topsoil",
                category: "Aggregates & Earthwork",
                name: "Screened Topsoil",
                aliases: ["Finish Topsoil", "Pulverized Topsoil"],
                unit: .cubicYard,
                conversionNote: nil,
                priceMin: 28, priceMax: 45, priceAvg: 36.50,
                jobTypes: ["septic_systems", "french_drains", "basements", "swimming_pools", "driveways"]
            ),
            PriceCatalogItem(
                id: "conc-readymix-4000",
                category: "Concrete & Reinforcement",
                name: "Ready-Mix Concrete (3,500–4,000 PSI, Air-Entrained)",
                aliases: ["4000 PSI Exterior Mix", "Air-Entrained Concrete"],
                unit: .cubicYard,
                conversionNote: nil,
                priceMin: 130, priceMax: 165, priceAvg: 147.50,
                jobTypes: ["concrete_pads", "basements", "driveways", "swimming_pools"]
            ),
            PriceCatalogItem(
                id: "conc-rebar-4",
                category: "Concrete & Reinforcement",
                name: "#4 Rebar (1/2\" × 20′ Stick)",
                aliases: ["Half-Inch Rebar", "Grade 60 Rebar"],
                unit: .stick20ft,
                conversionNote: nil,
                priceMin: 11, priceMax: 15, priceAvg: 13,
                jobTypes: ["basements", "concrete_pads", "swimming_pools"]
            ),
            PriceCatalogItem(
                id: "conc-wire-mesh",
                category: "Concrete & Reinforcement",
                name: "6×6 Welded Wire Mesh (8′×20′ Sheet)",
                aliases: ["Remesh Sheet", "W1.4/W2.9 Wire Mesh"],
                unit: .sheet8x20,
                conversionNote: nil,
                priceMin: 30, priceMax: 65, priceAvg: 47.50,
                jobTypes: ["concrete_pads", "driveways", "swimming_pools"]
            ),
            PriceCatalogItem(
                id: "conc-vapor-barrier",
                category: "Concrete & Reinforcement",
                name: "Vapor Barrier (6-mil to 10-mil Poly, 20′×100′ Roll)",
                aliases: ["Under-Slab Poly", "Visqueen"],
                unit: .roll2000sqft,
                conversionNote: nil,
                priceMin: 75, priceMax: 140, priceAvg: 107.50,
                jobTypes: ["basements", "concrete_pads"]
            ),
            PriceCatalogItem(
                id: "conc-expansion-joint",
                category: "Concrete & Reinforcement",
                name: "Expansion Joint Strip (10′ Length)",
                aliases: ["Fiber Expansion Joint", "Foam Expansion Joint"],
                unit: .piece10ft,
                conversionNote: nil,
                priceMin: 8, priceMax: 14, priceAvg: 11,
                jobTypes: ["concrete_pads", "driveways", "swimming_pools"]
            ),
            PriceCatalogItem(
                id: "drain-perf-hdpe",
                category: "Drainage & Geotextiles",
                name: "4\" Perforated Corrugated HDPE Pipe (100′ Roll)",
                aliases: ["ADS Pipe", "Tile Pipe", "Sock Pipe"],
                unit: .roll100ft,
                conversionNote: nil,
                priceMin: 70, priceMax: 125, priceAvg: 97.50,
                jobTypes: ["french_drains", "basements"]
            ),
            PriceCatalogItem(
                id: "drain-solid-pvc",
                category: "Drainage & Geotextiles",
                name: "4\" Solid SDR-35 / Schedule 40 PVC Pipe",
                aliases: ["SDR-35 Pipe", "Sch 40 PVC", "Tightline Pipe"],
                unit: .linearFoot,
                conversionNote: nil,
                priceMin: 1.80, priceMax: 3.20, priceAvg: 2.50,
                jobTypes: ["french_drains", "septic_systems", "basements"]
            ),
            PriceCatalogItem(
                id: "geo-nonwoven-filter",
                category: "Drainage & Geotextiles",
                name: "Non-Woven Geotextile Filter Fabric (4–6 oz)",
                aliases: ["Drainage Fabric", "Trench Fabric", "Mirafi 140N"],
                unit: .roll,
                conversionNote: "Standard rolls ~1,800 to 4,500 sq ft ($0.08–$0.15/sq ft)",
                priceMin: 180, priceMax: 320, priceAvg: 250,
                jobTypes: ["french_drains", "basements"]
            ),
            PriceCatalogItem(
                id: "geo-woven-stabilization",
                category: "Drainage & Geotextiles",
                name: "Woven Stabilization Geotextile Fabric",
                aliases: ["Road Fabric", "Driveway Fabric", "Mirafi 500X/600X"],
                unit: .roll,
                conversionNote: "Standard rolls ~4,500 to 5,400 sq ft",
                priceMin: 350, priceMax: 550, priceAvg: 450,
                jobTypes: ["driveways", "concrete_pads"]
            ),
            PriceCatalogItem(
                id: "drain-basins-emitters",
                category: "Drainage & Geotextiles",
                name: "Catch Basins & Pop-Up Emitters",
                aliases: ["Yard Drain Box", "NDS Catch Basin", "Pop-Up Drain"],
                unit: .each,
                conversionNote: nil,
                priceMin: 15, priceMax: 45, priceAvg: 30,
                jobTypes: ["french_drains", "driveways"]
            ),
            PriceCatalogItem(
                id: "drain-pvc-fittings",
                category: "Drainage & Geotextiles",
                name: "4\" PVC Drainage Fittings (Wyes, Elbows, Couplers)",
                aliases: ["SDR-35 Fittings", "Sch 40 Fittings"],
                unit: .each,
                conversionNote: nil,
                priceMin: 4, priceMax: 12, priceAvg: 8,
                jobTypes: ["french_drains", "septic_systems", "basements"]
            ),
            PriceCatalogItem(
                id: "erosion-silt-fence",
                category: "Drainage & Geotextiles",
                name: "Silt Fence (3′ × 100′ with Wooden Stakes)",
                aliases: ["E&S Fence", "Sediment Barrier"],
                unit: .roll100ft,
                conversionNote: nil,
                priceMin: 35, priceMax: 55, priceAvg: 45,
                jobTypes: ["basements", "septic_systems", "swimming_pools", "site_prep"]
            ),
            PriceCatalogItem(
                id: "septic-tank-1000-conc",
                category: "Septic System Components",
                name: "1,000-Gallon Precast Concrete Septic Tank",
                aliases: ["1000 Gal Concrete Tank"],
                unit: .each,
                conversionNote: nil,
                priceMin: 950, priceMax: 1500, priceAvg: 1225,
                jobTypes: ["septic_systems"]
            ),
            PriceCatalogItem(
                id: "septic-tank-1000-poly",
                category: "Septic System Components",
                name: "1,000-Gallon Polyethylene Septic Tank",
                aliases: ["1000 Gal Plastic Tank", "Norwesco/Infiltrator Tank"],
                unit: .each,
                conversionNote: nil,
                priceMin: 1400, priceMax: 2300, priceAvg: 1850,
                jobTypes: ["septic_systems"]
            ),
            PriceCatalogItem(
                id: "septic-tank-1500",
                category: "Septic System Components",
                name: "1,500-Gallon Septic Tank (Concrete or Poly)",
                aliases: ["1500 Gal Tank"],
                unit: .each,
                conversionNote: nil,
                priceMin: 1600, priceMax: 3200, priceAvg: 2400,
                jobTypes: ["septic_systems"]
            ),
            PriceCatalogItem(
                id: "septic-leach-chambers",
                category: "Septic System Components",
                name: "Plastic Leaching Chambers (4′ Section)",
                aliases: ["Infiltrator Quick4", "Leach Field Chambers"],
                unit: .each4ft,
                conversionNote: nil,
                priceMin: 30, priceMax: 45, priceAvg: 37.50,
                jobTypes: ["septic_systems"]
            ),
            PriceCatalogItem(
                id: "septic-dbox",
                category: "Septic System Components",
                name: "Distribution Box (Concrete or Poly)",
                aliases: ["D-Box", "Septic Distribution Box"],
                unit: .each,
                conversionNote: nil,
                priceMin: 90, priceMax: 180, priceAvg: 135,
                jobTypes: ["septic_systems"]
            ),
            PriceCatalogItem(
                id: "septic-riser-lid",
                category: "Septic System Components",
                name: "Septic Tank Riser & Lid Assembly (20\"–24\")",
                aliases: ["Access Riser", "Tuf-Tite Riser"],
                unit: .each,
                conversionNote: nil,
                priceMin: 75, priceMax: 150, priceAvg: 112.50,
                jobTypes: ["septic_systems"]
            )
        ]
    )

    static var `default`: RegionalPriceCatalog { .ohioPennsylvaniaWestVirginia }
}

extension MaterialKind {
    /// Price Book id used when estimating material cost for this kind.
    var priceCatalogId: String? {
        switch self {
        case .limestone2: return "agg-57-2b"
        case .bankRunGravel: return "agg-2a-304"
        case .sand: return "agg-mason-sand"
        case .concrete: return "conc-readymix-4000"
        case .excavatedDirt: return nil // haul-off — not a yard purchase line
        }
    }

    /// Billable catalog quantity for a computed layer volume (yd³ + optional tons).
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
