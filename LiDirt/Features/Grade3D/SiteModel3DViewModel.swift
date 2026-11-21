import Foundation
import Combine

@MainActor
final class SiteModel3DViewModel: ObservableObject {
    let existingHeightmap: HeightmapResult

    @Published var cutouts: [GradeCutout] = []
    @Published var selectedCutoutId: UUID?
    @Published var flaggedShape: FlagOutlinedShape = FlagOutlinedShape()
    @Published var selectedFlagId: UUID?
    @Published var showProposed = true
    @Published var statusMessage: String = "Add a slab, basement, or pool cutout — or place shape flags for a custom outline."
    @Published private(set) var proposedResult: ProposedGradeResult
    @Published var draftWidthFeet: String = "24"
    @Published var draftLengthFeet: String = "40"
    @Published var draftDepthFeet: String = "0.5"
    @Published var draftMeasuredFeet: String = ""
    @Published var measureFromFlagId: UUID?
    @Published var measureToFlagId: UUID?
    /// Per-cutout material assembly (slab on limestone, dig-only, …).
    @Published var assembliesByCutoutId: [UUID: MaterialAssembly] = [:]
    @Published private(set) var materialsEstimate: MaterialsEstimate = MaterialsEstimate(
        footprintAreaSquareFeet: 0,
        demCutCubicYards: 0,
        demFillCubicYards: 0,
        lineItems: [],
        assemblyName: "No assemblies",
        notes: [],
        priceRegion: nil,
        estimatedMaterialCostAvg: nil
    )

    init(heightmap: HeightmapResult) {
        self.existingHeightmap = heightmap
        self.proposedResult = ProposedGradeApplicator.apply(existing: heightmap, cutouts: [])
    }

    var selectedCutout: GradeCutout? {
        cutouts.first { $0.id == selectedCutoutId }
    }

    var displayHeightmap: HeightmapResult {
        showProposed ? proposedResult.proposed : existingHeightmap
    }

    var volumeSummary: String {
        let v = proposedResult.volume
        if v.cellsEdited == 0 && materialsEstimate.lineItems.isEmpty {
            return "No cut/fill yet — place a finished-work shape."
        }
        return String(
            format: "Cut %.1f yd³ · Fill %.1f yd³ · Net %.1f yd³",
            v.cutCubicYards,
            v.fillCubicYards,
            v.netCutCubicYards
        )
    }

    var selectedAssembly: MaterialAssembly? {
        guard let id = selectedCutoutId else { return nil }
        return assembliesByCutoutId[id]
    }

    func addPreset(_ preset: FinishWorkPreset) {
        let center = ProposedGradeApplicator.defaultCenter(for: existingHeightmap)
        var cutout = GradeCutout.fromPreset(
            preset,
            centerLocalX: center.x,
            centerLocalZ: center.z
        )
        // Custom starts from typed draft fields.
        if preset == .custom {
            cutout.widthFeet = Double(draftWidthFeet) ?? cutout.widthFeet
            cutout.lengthFeet = Double(draftLengthFeet) ?? cutout.lengthFeet
            cutout.depthFeet = Double(draftDepthFeet) ?? cutout.depthFeet
        }
        // Slab assembly needs dig room for 6″ gravel + 4″ concrete.
        if preset == .concreteSlab {
            cutout.depthFeet = MaterialAssembly.slabOnLimestone2.totalLayerThicknessInches / 12.0
        }
        cutouts.append(cutout)
        selectedCutoutId = cutout.id
        assembliesByCutoutId[cutout.id] = MaterialAssembly.default(for: preset)
        syncDraft(from: cutout)
        rebuild()
        statusMessage = "\(preset.displayName) placed — check Materials for dirt + gravel + concrete."
    }

    func setAssemblyForSelected(_ assembly: MaterialAssembly) {
        guard let id = selectedCutoutId else { return }
        assembliesByCutoutId[id] = assembly
        if assembly.excavateForLayers {
            let inches = assembly.totalLayerThicknessInches
            if let idx = cutouts.firstIndex(where: { $0.id == id }), inches > 0 {
                cutouts[idx].depthFeet = inches / 12.0
                syncDraft(from: cutouts[idx])
            }
        }
        rebuild()
        statusMessage = "Assembly: \(assembly.displayName)"
    }

    func syncDraft(from cutout: GradeCutout) {
        draftWidthFeet = String(format: "%g", cutout.widthFeet)
        draftLengthFeet = String(format: "%g", cutout.lengthFeet)
        draftDepthFeet = String(format: "%g", cutout.depthFeet)
    }

    func applyDraftToSelected() {
        guard let id = selectedCutoutId,
              let idx = cutouts.firstIndex(where: { $0.id == id }) else { return }
        if let w = Double(draftWidthFeet), w > 0 { cutouts[idx].widthFeet = w }
        if let l = Double(draftLengthFeet), l > 0 { cutouts[idx].lengthFeet = l }
        if let d = Double(draftDepthFeet), d >= 0 { cutouts[idx].depthFeet = d }
        rebuild()
        statusMessage = "Updated \(cutouts[idx].label) dimensions."
    }

    func nudgeSelected(dxFeet: Double, dzFeet: Double) {
        guard let id = selectedCutoutId,
              let idx = cutouts.firstIndex(where: { $0.id == id }) else { return }
        cutouts[idx].centerLocalX += dxFeet * 0.3048
        cutouts[idx].centerLocalZ += dzFeet * 0.3048
        rebuild()
    }

    func deleteSelectedCutout() {
        guard let id = selectedCutoutId else { return }
        cutouts.removeAll { $0.id == id }
        assembliesByCutoutId[id] = nil
        selectedCutoutId = cutouts.last?.id
        rebuild()
        statusMessage = "Removed cutout."
    }

    func clearAllCutouts() {
        cutouts.removeAll()
        assembliesByCutoutId.removeAll()
        selectedCutoutId = nil
        rebuild()
        statusMessage = "Cleared finished-work shapes."
    }

    // MARK: - Shape flags (complex outlines)

    func addFlagAtCenter() {
        let center = ProposedGradeApplicator.defaultCenter(for: existingHeightmap)
        let elev = sampleElevation(x: center.x, z: center.z) ?? existingHeightmap.bounds.minY
        let offset = Double(flaggedShape.flags.count) * 1.5
        let flag = ShapeFlag(
            label: ShapeFlagGeometry.nextLabel(after: flaggedShape.flags),
            localX: center.x + offset,
            localY: elev,
            localZ: center.z
        )
        flaggedShape.flags.append(flag)
        selectedFlagId = flag.id
        statusMessage = "Flag \(flag.label) placed — add more corners, then measure opposite flags."
        rebuild()
    }

    func nudgeSelectedFlag(dxFeet: Double, dzFeet: Double) {
        guard let id = selectedFlagId,
              let idx = flaggedShape.flags.firstIndex(where: { $0.id == id }) else { return }
        flaggedShape.flags[idx].localX += dxFeet * 0.3048
        flaggedShape.flags[idx].localZ += dzFeet * 0.3048
        if let elev = sampleElevation(x: flaggedShape.flags[idx].localX, z: flaggedShape.flags[idx].localZ) {
            flaggedShape.flags[idx].localY = elev
        }
        rebuild()
    }

    func deleteSelectedFlag() {
        guard let id = selectedFlagId else { return }
        flaggedShape.flags.removeAll { $0.id == id }
        flaggedShape.measurements.removeAll {
            $0.fromFlagId == id || $0.toFlagId == id
        }
        selectedFlagId = flaggedShape.flags.last?.id
        rebuild()
        statusMessage = "Removed flag."
    }

    func suggestOppositeMeasurements() {
        let pairs = ShapeFlagGeometry.suggestedOppositePairs(flags: flaggedShape.flags)
        guard !pairs.isEmpty else {
            statusMessage = "Need at least 4 flags to suggest opposite spans."
            return
        }
        for (a, b) in pairs {
            if ShapeFlagGeometry.measurement(in: flaggedShape, from: a, to: b) != nil { continue }
            guard let fa = flaggedShape.flags.first(where: { $0.id == a }),
                  let fb = flaggedShape.flags.first(where: { $0.id == b }) else { continue }
            let modelFt = ShapeFlagGeometry.modelDistanceFeet(from: fa, to: fb)
            flaggedShape.measurements.append(
                FlagSpanMeasurement(
                    fromFlagId: a,
                    toFlagId: b,
                    measuredFeet: modelFt,
                    kind: .opposite,
                    note: "Suggested — replace with taped feet"
                )
            )
        }
        statusMessage = "Opposite pairs ready — type taped feet for each span."
    }

    func addOrUpdateMeasurement() {
        guard let from = measureFromFlagId, let to = measureToFlagId, from != to,
              let feet = Double(draftMeasuredFeet), feet > 0 else {
            statusMessage = "Pick two flags and enter measured feet."
            return
        }
        if let idx = flaggedShape.measurements.firstIndex(where: {
            ($0.fromFlagId == from && $0.toFlagId == to)
                || ($0.fromFlagId == to && $0.toFlagId == from)
        }) {
            flaggedShape.measurements[idx].measuredFeet = feet
            flaggedShape.measurements[idx].kind = .opposite
            flaggedShape.measurements[idx].note = nil
        } else {
            flaggedShape.measurements.append(
                FlagSpanMeasurement(fromFlagId: from, toFlagId: to, measuredFeet: feet, kind: .opposite)
            )
        }
        statusMessage = String(format: "Saved %.2f ft between flags.", feet)
    }

    func fitFlagsToOppositeMeasurements() {
        let before = flaggedShape
        flaggedShape = ShapeFlagGeometry.applyOppositeSpanScale(flaggedShape)
        if flaggedShape == before {
            statusMessage = "Add opposite-flag measurements first, then fit."
        } else {
            statusMessage = "Scaled outline to match taped opposite spans."
            rebuild()
        }
    }

    func rebuild() {
        let flagged = flaggedShape.flags.count >= 3 ? [flaggedShape] : []
        proposedResult = ProposedGradeApplicator.apply(
            existing: existingHeightmap,
            cutouts: cutouts,
            flaggedShapes: flagged
        )
        materialsEstimate = MaterialsCalculator.estimate(
            cutouts: cutouts,
            assembliesByCutoutId: assembliesByCutoutId,
            demVolume: proposedResult.volume,
            flaggedShapes: flagged
        )
    }

    private func sampleElevation(x: Double, z: Double) -> Double? {
        let col = Int(floor((x - existingHeightmap.originX) / existingHeightmap.cellSizeM))
        let row = Int(floor((z - existingHeightmap.originZ) / existingHeightmap.cellSizeM))
        guard col >= 0, row >= 0, col < existingHeightmap.width, row < existingHeightmap.height else {
            return nil
        }
        let elev = existingHeightmap.elevations[row * existingHeightmap.width + col]
        return elev.isNaN ? nil : Double(elev)
    }
}
