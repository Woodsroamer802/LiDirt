import Foundation

/// A stake / flag corner used to outline a complicated proposed shape on the grade model.
/// Distinct from scan `ControlPin` (known elevations): these map the *proposed work* outline.
struct ShapeFlag: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// Short field label (“A”, “B”, “NE”, …).
    var label: String
    /// Local DEM meters (+X / +Z ground, +Y up) — same frame as `HeightmapResult`.
    var localX: Double
    var localY: Double
    var localZ: Double
    /// Optional note (e.g. “NW corner of pool”).
    var note: String?

    init(
        id: UUID = UUID(),
        label: String,
        localX: Double,
        localY: Double,
        localZ: Double,
        note: String? = nil
    ) {
        self.id = id
        self.label = label
        self.localX = localX
        self.localY = localY
        self.localZ = localZ
        self.note = note
    }
}

enum FlagSpanKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Facing sides (typical width / length across the shape).
    case opposite
    /// Shared edge between neighboring flags in the ring.
    case edge
    /// Corner-to-corner check.
    case diagonal
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opposite: return "Opposite flags"
        case .edge: return "Adjacent edge"
        case .diagonal: return "Diagonal"
        case .custom: return "Custom span"
        }
    }
}

/// User-entered tape / laser measurement between two flags.
struct FlagSpanMeasurement: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var fromFlagId: UUID
    var toFlagId: UUID
    /// Measured distance in feet (what the crew taped in the field).
    var measuredFeet: Double
    var kind: FlagSpanKind
    var note: String?

    init(
        id: UUID = UUID(),
        fromFlagId: UUID,
        toFlagId: UUID,
        measuredFeet: Double,
        kind: FlagSpanKind = .opposite,
        note: String? = nil
    ) {
        self.id = id
        self.fromFlagId = fromFlagId
        self.toFlagId = toFlagId
        self.measuredFeet = measuredFeet
        self.kind = kind
        self.note = note
    }
}

/// Ordered ring of flags plus optional opposite-flag (and other) measurements.
struct FlagOutlinedShape: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    /// Ring order around the outline (first connects to last when closed).
    var flags: [ShapeFlag]
    var measurements: [FlagSpanMeasurement]
    /// Dig / level parameters once this outline becomes a cutout.
    var digMode: GradeEditMode
    var depthFeet: Double
    var targetElevationM: Double?

    init(
        id: UUID = UUID(),
        name: String = "Flagged outline",
        flags: [ShapeFlag] = [],
        measurements: [FlagSpanMeasurement] = [],
        digMode: GradeEditMode = .digBelowSurface,
        depthFeet: Double = 2,
        targetElevationM: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.flags = flags
        self.measurements = measurements
        self.digMode = digMode
        self.depthFeet = depthFeet
        self.targetElevationM = targetElevationM
    }
}

/// Pure helpers for flag rings and opposite-span prep (no SceneKit).
enum ShapeFlagGeometry {
    static func nextLabel(after existing: [ShapeFlag]) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let used = Set(existing.map(\.label.uppercased()))
        for ch in letters {
            let s = String(ch)
            if !used.contains(s) { return s }
        }
        return "F\(existing.count + 1)"
    }

    /// Horizontal distance in feet between two flags (model space).
    static func modelDistanceFeet(from a: ShapeFlag, to b: ShapeFlag) -> Double {
        let dx = b.localX - a.localX
        let dz = b.localZ - a.localZ
        let meters = (dx * dx + dz * dz).squareRoot()
        return meters / 0.3048
    }

    static func measurement(
        in shape: FlagOutlinedShape,
        from fromId: UUID,
        to toId: UUID
    ) -> FlagSpanMeasurement? {
        shape.measurements.first {
            ($0.fromFlagId == fromId && $0.toFlagId == toId)
                || ($0.fromFlagId == toId && $0.toFlagId == fromId)
        }
    }

    /// Suggest opposite pairs for a closed ring (i → i + n/2). Odd counts skip the last leftover.
    static func suggestedOppositePairs(flags: [ShapeFlag]) -> [(UUID, UUID)] {
        let n = flags.count
        guard n >= 4 else { return [] }
        let half = n / 2
        var pairs: [(UUID, UUID)] = []
        var seen = Set<String>()
        for i in 0..<half {
            let j = (i + half) % n
            let a = flags[i].id
            let b = flags[j].id
            let key = [a.uuidString, b.uuidString].sorted().joined(separator: "|")
            if seen.insert(key).inserted {
                pairs.append((a, b))
            }
        }
        return pairs
    }

    /// Scale factors from measured opposite spans vs current model distances.
    /// Returns average scale (measured / model) when at least one opposite measurement exists.
    static func oppositeSpanScaleFactor(shape: FlagOutlinedShape) -> Double? {
        var ratios: [Double] = []
        for m in shape.measurements where m.kind == .opposite || m.kind == .diagonal {
            guard m.measuredFeet > 0,
                  let a = shape.flags.first(where: { $0.id == m.fromFlagId }),
                  let b = shape.flags.first(where: { $0.id == m.toFlagId }) else { continue }
            let modelFt = modelDistanceFeet(from: a, to: b)
            guard modelFt > 1e-6 else { continue }
            ratios.append(m.measuredFeet / modelFt)
        }
        guard !ratios.isEmpty else { return nil }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    /// Uniformly scale flag XY about the ring centroid using opposite-span measurements.
    /// Prep for fitting a sketched outline to taped field dimensions.
    static func applyOppositeSpanScale(_ shape: FlagOutlinedShape) -> FlagOutlinedShape {
        guard let scale = oppositeSpanScaleFactor(shape: shape), abs(scale - 1) > 1e-6 else {
            return shape
        }
        guard !shape.flags.isEmpty else { return shape }
        let cx = shape.flags.map(\.localX).reduce(0, +) / Double(shape.flags.count)
        let cz = shape.flags.map(\.localZ).reduce(0, +) / Double(shape.flags.count)
        var next = shape
        next.flags = shape.flags.map { flag in
            var f = flag
            f.localX = cx + (flag.localX - cx) * scale
            f.localZ = cz + (flag.localZ - cz) * scale
            return f
        }
        return next
    }

    /// Point-in-polygon (ray cast) for a closed flag ring in local XZ.
    static func contains(localX x: Double, localZ z: Double, ring: [ShapeFlag]) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let xi = ring[i].localX
            let zi = ring[i].localZ
            let xj = ring[j].localX
            let zj = ring[j].localZ
            let intersect = ((zi > z) != (zj > z))
                && (x < (xj - xi) * (z - zi) / max((zj - zi), 1e-12) + xi)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }
}
