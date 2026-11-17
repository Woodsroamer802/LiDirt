import Foundation

/// Horizontal footprint for a proposed-grade cutout on the DEM.
enum CutoutShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case rectangle
    case circle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        }
    }
}

/// How the cutout changes elevations inside its footprint.
enum GradeEditMode: String, Codable, CaseIterable, Sendable {
    /// Lower each cell by `depthFeet` from the existing surface (basement / pool dig).
    case digBelowSurface
    /// Flatten to a single absolute elevation (cut-and-level slab pad).
    case setAbsoluteElevation

    var displayName: String {
        switch self {
        case .digBelowSurface: return "Dig below surface"
        case .setAbsoluteElevation: return "Level to elevation"
        }
    }
}

/// Customer-demo presets for finished work shapes.
enum FinishWorkPreset: String, CaseIterable, Identifiable, Sendable {
    case concreteSlab
    case basement
    case swimmingPool
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .concreteSlab: return "Concrete slab"
        case .basement: return "Basement dig"
        case .swimmingPool: return "Swimming pool"
        case .custom: return "Custom cutout"
        }
    }

    var helpText: String {
        switch self {
        case .concreteSlab:
            return "Cut and level a pad for a slab — rectangle flattened to one grade."
        case .basement:
            return "Rectangular excavation to basement depth below today’s surface."
        case .swimmingPool:
            return "Circular pool cutout dug below the existing grade."
        case .custom:
            return "Type your own shape, size, and dig depth or level elevation."
        }
    }

    /// Default dimensions in feet (width × length × depth). Circle uses width as diameter.
    var defaultWidthFeet: Double {
        switch self {
        case .concreteSlab: return 24
        case .basement: return 32
        case .swimmingPool: return 18
        case .custom: return 20
        }
    }

    var defaultLengthFeet: Double {
        switch self {
        case .concreteSlab: return 40
        case .basement: return 48
        case .swimmingPool: return 18
        case .custom: return 20
        }
    }

    var defaultDepthFeet: Double {
        switch self {
        case .concreteSlab: return 0.5
        case .basement: return 9
        case .swimmingPool: return 5
        case .custom: return 2
        }
    }

    var shape: CutoutShape {
        switch self {
        case .swimmingPool: return .circle
        case .concreteSlab, .basement, .custom: return .rectangle
        }
    }

    var mode: GradeEditMode {
        switch self {
        case .concreteSlab: return .setAbsoluteElevation
        case .basement, .swimmingPool, .custom: return .digBelowSurface
        }
    }
}

/// One editable proposed-work cutout in the scan’s local meter frame (+X / +Z ground, +Y up).
struct GradeCutout: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var label: String
    var shape: CutoutShape
    var mode: GradeEditMode
    /// Feet across (circle = diameter).
    var widthFeet: Double
    /// Feet along length (ignored for circle).
    var lengthFeet: Double
    /// Dig depth in feet (dig mode), or ignored when leveling to an absolute elevation.
    var depthFeet: Double
    /// Absolute target elevation in meters (level-pad mode). `nil` → use mean of cells in footprint.
    var targetElevationM: Double?
    /// Center in local DEM meters (same frame as `HeightmapResult.originX/Z`).
    var centerLocalX: Double
    var centerLocalZ: Double
    /// Rotation about +Y, degrees clockwise when viewed from above.
    var rotationDegrees: Double

    init(
        id: UUID = UUID(),
        label: String,
        shape: CutoutShape,
        mode: GradeEditMode,
        widthFeet: Double,
        lengthFeet: Double,
        depthFeet: Double,
        targetElevationM: Double? = nil,
        centerLocalX: Double,
        centerLocalZ: Double,
        rotationDegrees: Double = 0
    ) {
        self.id = id
        self.label = label
        self.shape = shape
        self.mode = mode
        self.widthFeet = widthFeet
        self.lengthFeet = lengthFeet
        self.depthFeet = depthFeet
        self.targetElevationM = targetElevationM
        self.centerLocalX = centerLocalX
        self.centerLocalZ = centerLocalZ
        self.rotationDegrees = rotationDegrees
    }

    static func fromPreset(
        _ preset: FinishWorkPreset,
        centerLocalX: Double,
        centerLocalZ: Double
    ) -> GradeCutout {
        GradeCutout(
            label: preset.displayName,
            shape: preset.shape,
            mode: preset.mode,
            widthFeet: preset.defaultWidthFeet,
            lengthFeet: preset.defaultLengthFeet,
            depthFeet: preset.defaultDepthFeet,
            targetElevationM: nil,
            centerLocalX: centerLocalX,
            centerLocalZ: centerLocalZ
        )
    }

    var widthM: Double { widthFeet * 0.3048 }
    var lengthM: Double { lengthFeet * 0.3048 }
    var depthM: Double { depthFeet * 0.3048 }

    /// Horizontal footprint area in square feet (circle uses width as diameter).
    var footprintAreaSquareFeet: Double {
        switch shape {
        case .circle:
            let r = widthFeet * 0.5
            return .pi * r * r
        case .rectangle:
            return max(widthFeet, 0) * max(lengthFeet, 0)
        }
    }

    /// Returns true if local-meter point `(x,z)` lies inside this cutout footprint.
    func contains(localX x: Double, localZ z: Double) -> Bool {
        let dx = x - centerLocalX
        let dz = z - centerLocalZ
        let rad = rotationDegrees * .pi / 180
        // Un-rotate (clockwise rotation → counter-rotate for local axes).
        let cosR = cos(-rad)
        let sinR = sin(-rad)
        let lx = dx * cosR - dz * sinR
        let lz = dx * sinR + dz * cosR

        switch shape {
        case .circle:
            let r = widthM * 0.5
            return (lx * lx + lz * lz) <= r * r
        case .rectangle:
            let halfW = widthM * 0.5
            let halfL = lengthM * 0.5
            return abs(lx) <= halfW && abs(lz) <= halfL
        }
    }
}

struct ProposedGradeVolume: Equatable, Sendable {
    /// Cubic yards of material removed (existing above proposed).
    var cutCubicYards: Double
    /// Cubic yards of material added (proposed above existing).
    var fillCubicYards: Double
    var cellsEdited: Int

    var netCutCubicYards: Double { cutCubicYards - fillCubicYards }
}

struct ProposedGradeResult: Sendable {
    var existing: HeightmapResult
    var proposed: HeightmapResult
    var volume: ProposedGradeVolume
}
