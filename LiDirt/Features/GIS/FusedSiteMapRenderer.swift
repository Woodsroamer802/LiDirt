import Foundation
import CoreLocation
import MapKit
import UIKit

/// Builds a **new** Job Site map image from fused elevation (USGS 3DEP foundation + phone LiDAR),
/// placed with GPS — hillshade + contours at any pad scale (not limited by USGS print tile zoom).
enum FusedSiteMapRenderer {
    /// Fallback long edge when bounds aren’t known yet.
    static let longEdgePixels: CGFloat = 4096
    /// Target detail for small pads — keeps ~140 sq ft sites sharp on phone.
    static let pixelsPerFoot: CGFloat = 32
    static let minLongEdgePixels: CGFloat = 1536
    static let maxLongEdgePixels: CGFloat = 4096

    struct RenderedMap: Sendable {
        var pngData: Data
        var bounds: JobSiteBounds
        var pixelWidth: Int
        var pixelHeight: Int

        var image: UIImage? { UIImage(data: pngData) }
    }

    /// Adaptive resolution: small Job Sites get more pixels per foot so zoom isn’t soft.
    static func longEdgePixels(for bounds: JobSiteBounds) -> CGFloat {
        let feet = CGFloat(max(bounds.sideFeetNS, bounds.sideFeetEW, 1))
        let target = feet * pixelsPerFoot
        return min(max(target, minLongEdgePixels), maxLongEdgePixels)
    }

    static func pixelSize(for bounds: JobSiteBounds, longEdge: CGFloat? = nil) -> CGSize {
        let edge = longEdge ?? longEdgePixels(for: bounds)
        let aspect = max(bounds.longitudeDelta, 1e-9) / max(bounds.latitudeDelta, 1e-9)
        if aspect >= 1 {
            return CGSize(width: edge, height: max(edge / aspect, 512))
        }
        return CGSize(width: max(edge * aspect, 512), height: edge)
    }

    /// Render hillshade + optional contours over `bounds` from a local-meter heightmap and GPS origin.
    /// - Parameter correctionYawRadians: legacy north-align fix when placing DEM on the map.
    static func render(
        heightmap: HeightmapResult,
        origin: CLLocationCoordinate2D,
        bounds: JobSiteBounds,
        intervalInches: Double,
        drawContours: Bool = true,
        buildings: [BuildingFootprint] = [],
        longEdge: CGFloat? = nil,
        correctionYawRadians: Double = 0
    ) -> RenderedMap? {
        guard bounds.isValid else { return nil }
        let size = pixelSize(for: bounds, longEdge: longEdge ?? longEdgePixels(for: bounds))
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 4, height > 4 else { return nil }

        var elevations = [Float](repeating: .nan, count: width * height)
        var minElev = Float.greatestFiniteMagnitude
        var maxElev = -Float.greatestFiniteMagnitude
        // Map → DEM: undo the display correction so we sample the stored grid.
        let sampleYaw = -correctionYawRadians

        for row in 0..<height {
            let v = (Double(row) + 0.5) / Double(height)
            let lat = bounds.north - (bounds.north - bounds.south) * v
            for col in 0..<width {
                let u = (Double(col) + 0.5) / Double(width)
                let lon = bounds.west + (bounds.east - bounds.west) * u
                let local = ContourMapGeoref.localMeters(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    origin: origin
                )
                let dem = ContourMapGeoref.correctedLocal(
                    xEast: local.x,
                    zNorth: local.z,
                    yawRadians: sampleYaw
                )
                if let elev = sampleBilinear(heightmap, x: dem.x, z: dem.z) {
                    let f = Float(elev)
                    elevations[row * width + col] = f
                    minElev = min(minElev, f)
                    maxElev = max(maxElev, f)
                }
            }
        }

        guard minElev.isFinite, maxElev.isFinite, maxElev > minElev else { return nil }

        let format = UIGraphicsImageRendererFormat()
        // Retina-scale bitmap so MapKit overlay stays sharp on device.
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.interpolationQuality = .high
            // Base fill
            UIColor(red: 0.14, green: 0.17, blue: 0.20, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let range = max(maxElev - minElev, 1e-3)
            for row in 0..<height {
                for col in 0..<width {
                    let idx = row * width + col
                    let elev = elevations[idx]
                    guard !elev.isNaN else { continue }
                    let shade = hillshade(
                        elevations: elevations,
                        width: width,
                        height: height,
                        col: col,
                        row: row
                    )
                    let t = CGFloat((elev - minElev) / range)
                    // Earth-tone elevation ramp × hillshade
                    let r = (0.22 + 0.55 * t) * CGFloat(shade)
                    let g = (0.28 + 0.42 * t) * CGFloat(shade)
                    let b = (0.20 + 0.28 * (1 - t)) * CGFloat(shade)
                    cg.setFillColor(UIColor(red: r, green: g, blue: b, alpha: 1).cgColor)
                    cg.fill(CGRect(x: col, y: row, width: 1, height: 1))
                }
            }

            if drawContours {
                let intervalM = max(intervalInches * 0.0254, 1e-4)
                let segs = ContourPreview.localSegments(
                    heightmap: heightmap,
                    intervalM: intervalM,
                    maxLevels: 60
                )
                let yellow = UIColor(red: 0.96, green: 0.78, blue: 0.12, alpha: 0.95).cgColor
                cg.setStrokeColor(yellow)
                cg.setLineWidth(max(1.2, CGFloat(width) / 900))
                cg.setLineJoin(.round)
                cg.setLineCap(.round)

                for seg in segs {
                    guard let a = pixel(
                        localX: seg.ax,
                        localZ: seg.az,
                        origin: origin,
                        bounds: bounds,
                        width: width,
                        height: height,
                        correctionYawRadians: correctionYawRadians
                    ),
                          let b = pixel(
                            localX: seg.bx,
                            localZ: seg.bz,
                            origin: origin,
                            bounds: bounds,
                            width: width,
                            height: height,
                            correctionYawRadians: correctionYawRadians
                          ) else {
                        continue
                    }
                    cg.move(to: a)
                    cg.addLine(to: b)
                    cg.strokePath()
                }
            }

            // Building outlines + fill (OpenStreetMap footprints) — site-plan style shading.
            if !buildings.isEmpty {
                let fill = UIColor(red: 0.55, green: 0.62, blue: 0.72, alpha: 0.45).cgColor
                let stroke = UIColor(red: 0.18, green: 0.28, blue: 0.42, alpha: 0.95).cgColor
                cg.setLineWidth(max(1.5, CGFloat(width) / 700))
                cg.setLineDash(phase: 0, lengths: [])
                cg.setLineJoin(.round)
                for building in buildings {
                    guard let path = buildingPath(
                        building.coordinates,
                        bounds: bounds,
                        width: width,
                        height: height
                    ) else { continue }
                    cg.addPath(path)
                    cg.setFillColor(fill)
                    cg.fillPath()
                    cg.addPath(path)
                    cg.setStrokeColor(stroke)
                    cg.strokePath()
                }
            }

            // Job Site frame
            cg.setStrokeColor(UIColor(red: 0.96, green: 0.78, blue: 0.12, alpha: 0.85).cgColor)
            cg.setLineWidth(max(2, CGFloat(width) / 500))
            cg.setLineDash(phase: 0, lengths: [8, 5])
            cg.stroke(CGRect(x: 2, y: 2, width: width - 4, height: height - 4))
        }

        guard let pngData = image.pngData() else { return nil }
        return RenderedMap(pngData: pngData, bounds: bounds, pixelWidth: width, pixelHeight: height)
    }

    private static func pixel(
        localX: Double,
        localZ: Double,
        origin: CLLocationCoordinate2D,
        bounds: JobSiteBounds,
        width: Int,
        height: Int,
        correctionYawRadians: Double = 0
    ) -> CGPoint? {
        let coord = ContourMapGeoref.coordinate(
            localXMetersEast: localX,
            localZMetersNorth: localZ,
            origin: origin,
            correctionYawRadians: correctionYawRadians
        )
        return mapPixel(coordinate: coord, bounds: bounds, width: width, height: height)
    }

    private static func mapPixel(
        coordinate: CLLocationCoordinate2D,
        bounds: JobSiteBounds,
        width: Int,
        height: Int
    ) -> CGPoint? {
        let u = (coordinate.longitude - bounds.west) / max(bounds.east - bounds.west, 1e-12)
        let v = (bounds.north - coordinate.latitude) / max(bounds.north - bounds.south, 1e-12)
        guard u >= -0.02, u <= 1.02, v >= -0.02, v <= 1.02 else { return nil }
        return CGPoint(x: u * Double(width), y: v * Double(height))
    }

    private static func buildingPath(
        _ coordinates: [CLLocationCoordinate2D],
        bounds: JobSiteBounds,
        width: Int,
        height: Int
    ) -> CGPath? {
        guard coordinates.count >= 3 else { return nil }
        let path = CGMutablePath()
        var started = false
        for coordinate in coordinates {
            guard let point = mapPixel(coordinate: coordinate, bounds: bounds, width: width, height: height) else {
                continue
            }
            if !started {
                path.move(to: point)
                started = true
            } else {
                path.addLine(to: point)
            }
        }
        guard started else { return nil }
        path.closeSubpath()
        return path
    }

    private static func hillshade(
        elevations: [Float],
        width: Int,
        height: Int,
        col: Int,
        row: Int
    ) -> Float {
        let c = elevations[row * width + col]
        guard !c.isNaN else { return 0.35 }
        let left = col > 0 ? elevations[row * width + col - 1] : c
        let right = col + 1 < width ? elevations[row * width + col + 1] : c
        let up = row > 0 ? elevations[(row - 1) * width + col] : c
        let down = row + 1 < height ? elevations[(row + 1) * width + col] : c
        let dzdx = (finite(right, c) - finite(left, c)) * 0.5
        let dzdy = (finite(down, c) - finite(up, c)) * 0.5
        // Light from northwest
        let lx: Float = -0.577
        let ly: Float = -0.577
        let lz: Float = 0.577
        let nx = -dzdx
        let ny = -dzdy
        let nz: Float = 1
        let inv = 1 / max(sqrt(nx * nx + ny * ny + nz * nz), 1e-6)
        let intensity = max(0, (nx * inv) * lx + (ny * inv) * ly + (nz * inv) * lz)
        return 0.35 + 0.65 * intensity
    }

    private static func finite(_ value: Float, _ fallback: Float) -> Float {
        value.isNaN ? fallback : value
    }

    private static func sampleBilinear(_ heightmap: HeightmapResult, x: Double, z: Double) -> Double? {
        let cell = max(heightmap.cellSizeM, 1e-9)
        let fx = (x - heightmap.originX) / cell - 0.5
        let fz = (z - heightmap.originZ) / cell - 0.5
        let x0 = Int(floor(fx))
        let z0 = Int(floor(fz))
        let x1 = x0 + 1
        let z1 = z0 + 1
        guard x0 >= 0, z0 >= 0, x1 < heightmap.width, z1 < heightmap.height else {
            // Nearest fallback near edges
            let cx = Int((x - heightmap.originX) / cell)
            let cz = Int((z - heightmap.originZ) / cell)
            guard cx >= 0, cz >= 0, cx < heightmap.width, cz < heightmap.height else { return nil }
            let v = heightmap.elevations[cz * heightmap.width + cx]
            return v.isNaN ? nil : Double(v)
        }
        let tx = fx - Double(x0)
        let tz = fz - Double(z0)
        let v00 = heightmap.elevations[z0 * heightmap.width + x0]
        let v10 = heightmap.elevations[z0 * heightmap.width + x1]
        let v01 = heightmap.elevations[z1 * heightmap.width + x0]
        let v11 = heightmap.elevations[z1 * heightmap.width + x1]
        if v00.isNaN || v10.isNaN || v01.isNaN || v11.isNaN { return nil }
        let a = Double(v00) * (1 - tx) + Double(v10) * tx
        let b = Double(v01) * (1 - tx) + Double(v11) * tx
        return a * (1 - tz) + b * tz
    }
}
