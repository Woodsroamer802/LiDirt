import Foundation
import simd

#if canImport(SceneKit)
import SceneKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct TerrainMeshBuffers: Sendable, Equatable {
    /// Interleaved positions in SceneKit meters (+Y up): x, y, z per vertex.
    var positions: [SIMD3<Float>]
    /// Triangle indices (UInt32), CCW when viewed from above for solid lighting.
    var indices: [UInt32]
    var minY: Float
    var maxY: Float
}

/// Builds a triangle mesh from a DEM heightmap for 3D proposed-grade viewing.
enum TerrainMeshBuilder {
    /// Vertical exaggeration helps shallow pads read as grade work on a phone screen.
    static let defaultVerticalExaggeration: Float = 1.5

    static func buildBuffers(
        heightmap: HeightmapResult,
        verticalExaggeration: Float = defaultVerticalExaggeration
    ) -> TerrainMeshBuffers? {
        let w = heightmap.width
        let h = heightmap.height
        guard w >= 2, h >= 2 else { return nil }

        var positions = [SIMD3<Float>](repeating: .zero, count: w * h)
        var minY = Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        var valid = [Bool](repeating: false, count: w * h)

        // Fill holes by nearest valid neighbor elevation for a continuous surface in the viewer.
        let filled = fillNaNsForMesh(heightmap.elevations, width: w, height: h)

        for row in 0..<h {
            for col in 0..<w {
                let idx = row * w + col
                guard let elev = filled[idx] else { continue }
                let x = Float(heightmap.originX + (Double(col) + 0.5) * heightmap.cellSizeM)
                let z = Float(heightmap.originZ + (Double(row) + 0.5) * heightmap.cellSizeM)
                let y = elev * verticalExaggeration
                positions[idx] = SIMD3(x, y, z)
                valid[idx] = true
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }

        guard minY <= maxY else { return nil }

        var indices: [UInt32] = []
        indices.reserveCapacity((w - 1) * (h - 1) * 6)
        for row in 0..<(h - 1) {
            for col in 0..<(w - 1) {
                let i00 = row * w + col
                let i10 = i00 + 1
                let i01 = i00 + w
                let i11 = i01 + 1
                guard valid[i00], valid[i10], valid[i01], valid[i11] else { continue }
                indices.append(contentsOf: [
                    UInt32(i00), UInt32(i01), UInt32(i10),
                    UInt32(i10), UInt32(i01), UInt32(i11)
                ])
            }
        }
        guard !indices.isEmpty else { return nil }

        return TerrainMeshBuffers(
            positions: positions,
            indices: indices,
            minY: minY,
            maxY: maxY
        )
    }

#if canImport(SceneKit)
    static func makeGeometry(
        heightmap: HeightmapResult,
        verticalExaggeration: Float = defaultVerticalExaggeration
    ) -> SCNGeometry? {
        guard let buffers = buildBuffers(heightmap: heightmap, verticalExaggeration: verticalExaggeration) else {
            return nil
        }
        return makeGeometry(from: buffers)
    }

    static func makeGeometry(from buffers: TerrainMeshBuffers) -> SCNGeometry {
        var positions = buffers.positions
        let positionData = Data(
            bytes: &positions,
            count: positions.count * MemoryLayout<SIMD3<Float>>.stride
        )
        let positionSource = SCNGeometrySource(
            data: positionData,
            semantic: .vertex,
            vectorCount: positions.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        var indices = buffers.indices
        let indexData = Data(
            bytes: &indices,
            count: indices.count * MemoryLayout<UInt32>.size
        )
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geometry = SCNGeometry(sources: [positionSource], elements: [element])
        let material = SCNMaterial()
        #if canImport(UIKit)
        material.diffuse.contents = UIColor(red: 0.42, green: 0.40, blue: 0.30, alpha: 1)
        #endif
        material.roughness.contents = 0.85
        material.metalness.contents = 0.05
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }
#endif

    /// Replace NaNs with a flood-fill average of neighbors so the mesh stays watertight for viewing.
    static func fillNaNsForMesh(_ elevations: [Float], width: Int, height: Int) -> [Float?] {
        var out: [Float?] = elevations.map { $0.isNaN ? nil : $0 }
        for _ in 0..<4 {
            var next = out
            var changed = false
            for row in 0..<height {
                for col in 0..<width {
                    let idx = row * width + col
                    if out[idx] != nil { continue }
                    var sum: Float = 0
                    var count = 0
                    for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let r = row + dr
                        let c = col + dc
                        guard r >= 0, r < height, c >= 0, c < width else { continue }
                        if let v = out[r * width + c] {
                            sum += v
                            count += 1
                        }
                    }
                    if count > 0 {
                        next[idx] = sum / Float(count)
                        changed = true
                    }
                }
            }
            out = next
            if !changed { break }
        }
        return out
    }
}
