import Foundation

enum MaterialUnit: String, Codable, CaseIterable, Sendable {
    case cubicYards
    case squareFeet
    case tons

    var displayName: String {
        switch self {
        case .cubicYards: return "yd³"
        case .squareFeet: return "ft²"
        case .tons: return "tons"
        }
    }
}

enum MaterialKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case excavatedDirt
    case limestone2
    case concrete
    case bankRunGravel
    case sand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .excavatedDirt: return "Excavated dirt (haul off)"
        case .limestone2: return "#2 limestone gravel"
        case .concrete: return "Ready-mix concrete"
        case .bankRunGravel: return "Bank-run gravel"
        case .sand: return "Sand"
        }
    }

    /// Loose / compacted bulk density factor for ordering (tons per compacted yd³). Optional.
    /// Regional OH/PA/WV yards typically quote ~1.4–1.5 tons/yd³ for limestone.
    var tonsPerCubicYard: Double? {
        switch self {
        case .limestone2: return 1.45
        case .bankRunGravel: return 1.45
        case .sand: return 1.35
        case .concrete, .excavatedDirt: return nil
        }
    }

    /// Extra order factor for gravel (compaction / waste). 1.0 = net volume only.
    var orderFactor: Double {
        switch self {
        case .limestone2, .bankRunGravel, .sand: return 1.15
        case .concrete: return 1.05
        case .excavatedDirt: return 1.0
        }
    }
}

/// One layer in a finished-work assembly (thickness × footprint → volume).
struct MaterialLayerSpec: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var material: MaterialKind
    /// Compacted / placed thickness in inches.
    var thicknessInches: Double
    var note: String?

    init(
        id: UUID = UUID(),
        material: MaterialKind,
        thicknessInches: Double,
        note: String? = nil
    ) {
        self.id = id
        self.material = material
        self.thicknessInches = thicknessInches
        self.note = note
    }

    var thicknessFeet: Double { thicknessInches / 12.0 }
}

/// Named stack of layers for a finished product (e.g. slab on gravel).
struct MaterialAssembly: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var displayName: String
    var helpText: String
    var layers: [MaterialLayerSpec]
    /// When true, excavate = sum of layer thicknesses (infill dig), unless DEM cut is larger.
    var excavateForLayers: Bool

    /// 4″ concrete on 6″ #2 limestone — the common pad assembly.
    static let slabOnLimestone2 = MaterialAssembly(
        id: "slab_4in_on_limestone2_6in",
        displayName: "4″ slab on 6″ #2 limestone",
        helpText: "Cut/level pad, place 6″ #2 limestone, pour 4″ concrete.",
        layers: [
            MaterialLayerSpec(material: .limestone2, thicknessInches: 6, note: "Compacted base"),
            MaterialLayerSpec(material: .concrete, thicknessInches: 4, note: "Slab")
        ],
        excavateForLayers: true
    )

    static let limestoneBaseOnly = MaterialAssembly(
        id: "limestone2_6in",
        displayName: "6″ #2 limestone only",
        helpText: "Base course without slab pour quantities.",
        layers: [
            MaterialLayerSpec(material: .limestone2, thicknessInches: 6)
        ],
        excavateForLayers: true
    )

    static let basementDirtOnly = MaterialAssembly(
        id: "basement_dirt",
        displayName: "Basement excavation (dirt)",
        helpText: "Uses dig depth from the basement cutout for haul-off dirt.",
        layers: [],
        excavateForLayers: false
    )

    static let poolDirtOnly = MaterialAssembly(
        id: "pool_dirt",
        displayName: "Pool excavation (dirt)",
        helpText: "Uses dig depth from the pool cutout for haul-off dirt.",
        layers: [],
        excavateForLayers: false
    )

    static let catalog: [MaterialAssembly] = [
        .slabOnLimestone2,
        .limestoneBaseOnly,
        .basementDirtOnly,
        .poolDirtOnly
    ]

    static func `default`(for preset: FinishWorkPreset) -> MaterialAssembly {
        switch preset {
        case .concreteSlab: return .slabOnLimestone2
        case .basement: return .basementDirtOnly
        case .swimmingPool: return .poolDirtOnly
        case .custom: return .slabOnLimestone2
        }
    }

    var totalLayerThicknessInches: Double {
        layers.reduce(0) { $0 + $1.thicknessInches }
    }
}

struct MaterialLineItem: Identifiable, Equatable, Sendable {
    var id: UUID
    var material: MaterialKind
    var quantity: Double
    var unit: MaterialUnit
    var detail: String
    /// Optional secondary quantity (e.g. tons for gravel).
    var secondaryQuantity: Double?
    var secondaryUnit: MaterialUnit?
    /// Regional Price Book extended cost when a catalog match exists.
    var priceQuote: MaterialPriceQuote?

    init(
        id: UUID = UUID(),
        material: MaterialKind,
        quantity: Double,
        unit: MaterialUnit,
        detail: String,
        secondaryQuantity: Double? = nil,
        secondaryUnit: MaterialUnit? = nil,
        priceQuote: MaterialPriceQuote? = nil
    ) {
        self.id = id
        self.material = material
        self.quantity = quantity
        self.unit = unit
        self.detail = detail
        self.secondaryQuantity = secondaryQuantity
        self.secondaryUnit = secondaryUnit
        self.priceQuote = priceQuote
    }

    var summary: String {
        var s = String(format: "%@ — %.2f %@", material.displayName, quantity, unit.displayName)
        if let sq = secondaryQuantity, let su = secondaryUnit {
            s += String(format: " (≈ %.2f %@)", sq, su.displayName)
        }
        if let quote = priceQuote {
            s += " · " + quote.rangeSummary
        }
        return s
    }
}

struct MaterialsEstimate: Equatable, Sendable {
    var footprintAreaSquareFeet: Double
    var demCutCubicYards: Double
    var demFillCubicYards: Double
    var lineItems: [MaterialLineItem]
    var assemblyName: String
    var notes: [String]
    var priceRegion: String?
    var estimatedMaterialCostAvg: Double?

    var isEmpty: Bool { lineItems.isEmpty && demCutCubicYards <= 0 && demFillCubicYards <= 0 }

    var pricedLineItems: [MaterialLineItem] {
        lineItems.filter { $0.priceQuote != nil }
    }
}
