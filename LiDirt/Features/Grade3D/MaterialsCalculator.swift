import Foundation

/// Quantities for removed dirt and placed infill / slab layers from cutout footprints.
enum MaterialsCalculator {
    private static let cubicFeetPerCubicYard = 27.0

    static func estimate(
        cutouts: [GradeCutout],
        assembliesByCutoutId: [UUID: MaterialAssembly],
        demVolume: ProposedGradeVolume,
        flaggedShapes: [FlagOutlinedShape] = []
    ) -> MaterialsEstimate {
        var items: [MaterialLineItem] = []
        var notes: [String] = []
        var totalArea = 0.0
        var assemblyNames: [String] = []

        // Aggregate layer volumes by material so one slab + gravel line each.
        var layerCubicYards: [MaterialKind: Double] = [:]
        var layerDetails: [MaterialKind: [String]] = [:]
        var excavationFromAssembliesYd3 = 0.0

        for cutout in cutouts {
            let area = cutout.footprintAreaSquareFeet
            guard area > 0 else { continue }
            totalArea += area
            let assembly = assembliesByCutoutId[cutout.id]
                ?? inferredAssembly(for: cutout)
            assemblyNames.append(assembly.displayName)

            for layer in assembly.layers {
                let netYd3 = volumeCubicYards(areaSquareFeet: area, thicknessFeet: layer.thicknessFeet)
                let ordered = netYd3 * layer.material.orderFactor
                layerCubicYards[layer.material, default: 0] += ordered
                let inches = String(format: "%g″", layer.thicknessInches)
                layerDetails[layer.material, default: []].append(
                    "\(cutout.label): \(inches) over \(formatArea(area))"
                )
            }

            if assembly.excavateForLayers {
                let digInches = max(assembly.totalLayerThicknessInches, cutout.depthFeet * 12)
                let digYd3 = volumeCubicYards(areaSquareFeet: area, thicknessFeet: digInches / 12)
                excavationFromAssembliesYd3 += digYd3
                notes.append(
                    String(
                        format: "%@: plan dig ≈ %.0f″ for layers (%.2f yd³ by footprint).",
                        cutout.label,
                        digInches,
                        digYd3
                    )
                )
            } else if cutout.mode == .digBelowSurface, cutout.depthFeet > 0 {
                let digYd3 = volumeCubicYards(areaSquareFeet: area, thicknessFeet: cutout.depthFeet)
                excavationFromAssembliesYd3 += digYd3
                notes.append(
                    String(
                        format: "%@: dig %.2f ft × footprint ≈ %.2f yd³.",
                        cutout.label,
                        cutout.depthFeet,
                        digYd3
                    )
                )
            }
        }

        for shape in flaggedShapes where shape.flags.count >= 3 {
            // Approximate ring as polygon area later; MVP uses bounding box of flags.
            let area = polygonAreaSquareFeet(flags: shape.flags)
            guard area > 0 else { continue }
            totalArea += area
            let digYd3 = volumeCubicYards(areaSquareFeet: area, thicknessFeet: shape.depthFeet)
            excavationFromAssembliesYd3 += digYd3
            notes.append(
                String(format: "%@: flagged outline dig ≈ %.2f yd³.", shape.name, digYd3)
            )
            assemblyNames.append(shape.name)
        }

        // Dirt to remove: take the larger of DEM cut vs assembly dig plan.
        let dirtYd3 = max(demVolume.cutCubicYards, excavationFromAssembliesYd3)
        if dirtYd3 > 1e-6 {
            items.append(
                MaterialLineItem(
                    material: .excavatedDirt,
                    quantity: dirtYd3,
                    unit: .cubicYards,
                    detail: demVolume.cutCubicYards >= excavationFromAssembliesYd3
                        ? "From DEM cut (existing → proposed)"
                        : "From footprint × dig depth (plan)"
                )
            )
        }
        if demVolume.fillCubicYards > 1e-6 {
            notes.append(
                String(
                    format: "DEM also shows %.2f yd³ fill — confirm imported fill separately.",
                    demVolume.fillCubicYards
                )
            )
        }

        for material in MaterialKind.allCases {
            guard let yd3 = layerCubicYards[material], yd3 > 1e-6 else { continue }
            let detail = (layerDetails[material] ?? []).joined(separator: "; ")
            var tons: Double?
            if let tpy = material.tonsPerCubicYard {
                tons = yd3 * tpy
            }
            items.append(
                MaterialLineItem(
                    material: material,
                    quantity: yd3,
                    unit: .cubicYards,
                    detail: detail.isEmpty ? "Layer volume × order factor" : detail,
                    secondaryQuantity: tons,
                    secondaryUnit: tons == nil ? nil : .tons
                )
            )
        }

        let name = assemblyNames.isEmpty
            ? "No assemblies"
            : Array(Set(assemblyNames)).sorted().joined(separator: " · ")

        if totalArea > 0 {
            notes.insert(String(format: "Total footprint ≈ %@.", formatArea(totalArea)), at: 0)
        }
        notes.append("Quantities are planning estimates — not a certified takeoff.")

        return MaterialsEstimate(
            footprintAreaSquareFeet: totalArea,
            demCutCubicYards: demVolume.cutCubicYards,
            demFillCubicYards: demVolume.fillCubicYards,
            lineItems: items,
            assemblyName: name,
            notes: notes
        )
    }

    static func volumeCubicYards(areaSquareFeet: Double, thicknessFeet: Double) -> Double {
        max(areaSquareFeet, 0) * max(thicknessFeet, 0) / cubicFeetPerCubicYard
    }

    static func inferredAssembly(for cutout: GradeCutout) -> MaterialAssembly {
        let label = cutout.label.lowercased()
        if label.contains("slab") || cutout.mode == .setAbsoluteElevation {
            return .slabOnLimestone2
        }
        if label.contains("basement") { return .basementDirtOnly }
        if label.contains("pool") { return .poolDirtOnly }
        return .slabOnLimestone2
    }

    /// Shoelace area for a closed flag ring (local meters → ft²).
    static func polygonAreaSquareFeet(flags: [ShapeFlag]) -> Double {
        guard flags.count >= 3 else { return 0 }
        var sum = 0.0
        for i in 0..<flags.count {
            let j = (i + 1) % flags.count
            sum += flags[i].localX * flags[j].localZ
            sum -= flags[j].localX * flags[i].localZ
        }
        let areaM2 = abs(sum) * 0.5
        return areaM2 / (0.3048 * 0.3048)
    }

    private static func formatArea(_ sqFt: Double) -> String {
        String(format: "%.0f ft²", sqFt)
    }
}
