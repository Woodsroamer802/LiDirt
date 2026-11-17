import Foundation
import CoreGraphics
import UIKit
import CoreLocation

struct SiteMapPrintModel: Sendable {
    var projectName: String
    var sheet: PrintSheetSize
    var heightmap: HeightmapResult
    var origin: CLLocationCoordinate2D
    var intervalInches: Double
    var methodLabel: String
    var surfaceModeLabel: String
    var verticalBiasM: Double
    var lidarCellCount: Int
    var capturedAt: Date
}

enum SiteMapPDFRenderer {
    enum RenderError: LocalizedError {
        case noContours
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .noContours: return "No contour lines to print for this interval."
            case .writeFailed: return "Could not write the print PDF."
            }
        }
    }

    @MainActor
    static func render(_ model: SiteMapPrintModel) throws -> URL {
        let segs = ContourPreview.localSegments(
            heightmap: model.heightmap,
            intervalM: model.intervalInches * 0.0254,
            maxLevels: 120
        )
        guard !segs.isEmpty else { throw RenderError.noContours }

        let page = model.sheet.sizePoints
        let margin = model.sheet.marginInches * 72
        let titleH = model.sheet.titleBlockHeightInches * 72
        let mapRect = CGRect(
            x: margin,
            y: margin,
            width: page.width - margin * 2,
            height: page.height - margin * 2 - titleH
        )
        let titleRect = CGRect(
            x: margin,
            y: page.height - margin - titleH,
            width: page.width - margin * 2,
            height: titleH
        )

        let bounds = model.heightmap.bounds
        let worldW = max(bounds.maxX - bounds.minX, 1e-3)
        let worldH = max(bounds.maxZ - bounds.minZ, 1e-3)
        let scale = min(mapRect.width / worldW, mapRect.height / worldH) * 0.92
        let drawnW = worldW * scale
        let drawnH = worldH * scale
        let originX = mapRect.midX - drawnW / 2
        let originY = mapRect.midY + drawnH / 2

        func mapPoint(x: Double, z: Double) -> CGPoint {
            CGPoint(
                x: originX + CGFloat(x - bounds.minX) * scale,
                y: originY - CGFloat(z - bounds.minZ) * scale
            )
        }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "LiDirt — \(model.projectName)",
            kCGPDFContextCreator as String: "LiDirt"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: page), format: format)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let cg = ctx.cgContext

            // Sheet background
            UIColor.white.setFill()
            cg.fill(CGRect(origin: .zero, size: page))

            // Map frame
            UIColor.black.setStroke()
            cg.setLineWidth(1.5)
            cg.stroke(mapRect.insetBy(dx: -1, dy: -1))

            // Light grid every 10 ft when scale allows
            drawGrid(
                context: cg,
                bounds: bounds,
                mapPoint: mapPoint,
                mapRect: mapRect,
                metersPerGrid: 3.048 // 10 ft
            )

            // Contours — index every 5th level
            let levels = Set(segs.map(\.elevationM))
            let sortedLevels = levels.sorted()
            let indexSet = Set(sortedLevels.enumerated().compactMap { idx, level -> Double? in
                idx % 5 == 0 ? level : nil
            })

            for seg in segs {
                let isIndex = indexSet.contains(seg.elevationM)
                cg.setStrokeColor(UIColor.black.cgColor)
                cg.setLineWidth(isIndex ? 1.6 : 0.7)
                cg.move(to: mapPoint(x: seg.ax, z: seg.az))
                cg.addLine(to: mapPoint(x: seg.bx, z: seg.bz))
                cg.strokePath()
            }

            // LiDAR detail footprint outline
            let lidarOutline = [
                mapPoint(x: bounds.minX, z: bounds.minZ),
                mapPoint(x: bounds.maxX, z: bounds.minZ),
                mapPoint(x: bounds.maxX, z: bounds.maxZ),
                mapPoint(x: bounds.minX, z: bounds.maxZ)
            ]
            cg.setStrokeColor(UIColor(red: 0.85, green: 0.55, blue: 0.05, alpha: 1).cgColor)
            cg.setLineWidth(1.2)
            cg.setLineDash(phase: 0, lengths: [6, 4])
            cg.move(to: lidarOutline[0])
            for p in lidarOutline.dropFirst() { cg.addLine(to: p) }
            cg.closePath()
            cg.strokePath()
            cg.setLineDash(phase: 0, lengths: [])

            drawNorthArrow(in: cg, at: CGPoint(x: mapRect.maxX - 36, y: mapRect.minY + 48))
            drawScaleBar(
                in: cg,
                at: CGPoint(x: mapRect.minX + 16, y: mapRect.maxY - 28),
                metersPerPoint: 1 / scale
            )

            drawTitleBlock(
                in: cg,
                rect: titleRect,
                model: model,
                groundWidthM: worldW,
                groundHeightM: worldH,
                mapWidthPt: drawnW
            )
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiDirtPrint", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeName = model.projectName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let filename = "\(safeName)_\(model.sheet.rawValue).pdf"
        let url = dir.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw RenderError.writeFailed
        }
        return url
    }

    private static func drawGrid(
        context: CGContext,
        bounds: HeightmapBounds,
        mapPoint: (Double, Double) -> CGPoint,
        mapRect: CGRect,
        metersPerGrid: Double
    ) {
        context.saveGState()
        context.clip(to: mapRect)
        context.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
        context.setLineWidth(0.4)
        let startX = (bounds.minX / metersPerGrid).rounded(.down) * metersPerGrid
        let startZ = (bounds.minZ / metersPerGrid).rounded(.down) * metersPerGrid
        var x = startX
        while x <= bounds.maxX + 1e-6 {
            let a = mapPoint(x, bounds.minZ)
            let b = mapPoint(x, bounds.maxZ)
            context.move(to: a)
            context.addLine(to: b)
            x += metersPerGrid
        }
        var z = startZ
        while z <= bounds.maxZ + 1e-6 {
            let a = mapPoint(bounds.minX, z)
            let b = mapPoint(bounds.maxX, z)
            context.move(to: a)
            context.addLine(to: b)
            z += metersPerGrid
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func drawNorthArrow(in context: CGContext, at tip: CGPoint) {
        context.saveGState()
        context.setFillColor(UIColor.black.cgColor)
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(1)
        let path = CGMutablePath()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - 8, y: tip.y + 22))
        path.addLine(to: CGPoint(x: tip.x, y: tip.y + 16))
        path.addLine(to: CGPoint(x: tip.x + 8, y: tip.y + 22))
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        ("N" as NSString).draw(at: CGPoint(x: tip.x - 5, y: tip.y + 24), withAttributes: attrs)
        context.restoreGState()
    }

    private static func drawScaleBar(in context: CGContext, at origin: CGPoint, metersPerPoint: CGFloat) {
        let targetFeet: [CGFloat] = [10, 20, 50, 100, 200]
        let feet = targetFeet.first { ($0 * 0.3048 / metersPerPoint) >= 40 && ($0 * 0.3048 / metersPerPoint) <= 180 }
            ?? 50
        let barWidth = CGFloat(feet) * 0.3048 / metersPerPoint
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: origin.x, y: origin.y, width: barWidth / 2, height: 6))
        context.setStrokeColor(UIColor.black.cgColor)
        context.stroke(CGRect(x: origin.x, y: origin.y, width: barWidth, height: 6))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: UIColor.black
        ]
        ("0" as NSString).draw(at: CGPoint(x: origin.x, y: origin.y + 8), withAttributes: attrs)
        ("\(Int(feet)) ft" as NSString).draw(
            at: CGPoint(x: origin.x + barWidth - 24, y: origin.y + 8),
            withAttributes: attrs
        )
    }

    private static func drawTitleBlock(
        in context: CGContext,
        rect: CGRect,
        model: SiteMapPrintModel,
        groundWidthM: Double,
        groundHeightM: Double,
        mapWidthPt: CGFloat
    ) {
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(1.2)
        context.stroke(rect)

        let rf = groundWidthM * 3.28084
        let rd = groundHeightM * 3.28084
        let inchesOnPaper = mapWidthPt / 72
        let scaleRatio = rf / Double(inchesOnPaper)
        let scaleText = scaleRatio >= 10
            ? String(format: "1 in = %.0f ft", scaleRatio)
            : String(format: "1 in = %.1f ft", scaleRatio)

        let date = model.capturedAt.formatted(date: .abbreviated, time: .shortened)
        let intervalLabel: String
        if model.intervalInches < 1 {
            intervalLabel = String(format: "%g in", model.intervalInches)
        } else {
            intervalLabel = String(format: "%.2g in", model.intervalInches)
        }

        let lines = [
            "LiDirt contour map — heavy equipment planning aid",
            "Project: \(model.projectName)",
            "Sheet: \(model.sheet.label)  ·  Contour interval: \(intervalLabel)  ·  \(scaleText)",
            String(
                format: "Surface: %@  ·  Extent ≈ %.0f × %.0f ft  ·  Method: %@  ·  LiDAR cells: %d  ·  Bias: %.2f m",
                model.surfaceModeLabel, rf, rd, model.methodLabel, model.lidarCellCount, model.verticalBiasM
            ),
            "USGS 3DEP foundation + phone LiDAR detail (GPS/compass place). Not a certified survey. \(date)"
        ]

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        var y = rect.minY + 10
        for (i, line) in lines.enumerated() {
            let font = UIFont.systemFont(ofSize: i == 0 ? 13 : 10, weight: i == 0 ? .bold : .regular)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ]
            (line as NSString).draw(
                in: CGRect(x: rect.minX + 12, y: y, width: rect.width - 24, height: 16),
                withAttributes: attrs
            )
            y += i == 0 ? 18 : 15
        }
    }
}
