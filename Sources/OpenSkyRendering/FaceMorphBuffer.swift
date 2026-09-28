// FaceGen expression composition and its frame-safe GPU upload. TRI deltas
// are composed on the CPU because the named target set is sparse; the vertex
// shader reads one position and normal delta pair per face vertex before
// skinning.

import Foundation
import Metal
import OpenSkyFormatsMesh
import simd

nonisolated public enum FaceMorphError: Error, Equatable {
    case vertexCountMismatch(tri: Int, mesh: Int)
    case bufferAllocationFailed
}

nonisolated public struct FaceMorphTarget: Sendable {
    public let name: String
    public let deltas: [MorphVertexDelta]
}

nonisolated public enum FaceMorphComposer: Sendable {
    public static func targets(from tri: TRIFile) -> [FaceMorphTarget] {
        let baseNormals = normals(vertices: tri.baseVertices, triangles: tri.triangles)
        return tri.morphTargets.map { target in
            let positions = zip(tri.baseVertices, target.scaledDeltas).map(+)
            let morphedNormals = normals(vertices: positions, triangles: tri.triangles)
            return FaceMorphTarget(
                name: target.name,
                deltas: zip(target.scaledDeltas, zip(morphedNormals, baseNormals)).map {
                    MorphVertexDelta(position: $0.0, normal: $0.1.0 - $0.1.1)
                }
            )
        }
    }

    public static func compose(
        targets: [FaceMorphTarget],
        weights: [String: Float],
        vertexCount: Int
    ) -> [MorphVertexDelta] {
        var positions = [SIMD3<Float>](repeating: .zero, count: vertexCount)
        var normals = [SIMD3<Float>](repeating: .zero, count: vertexCount)
        for target in targets {
            let weight = min(max(weights[target.name] ?? 0, 0), 1)
            guard weight > 0, target.deltas.count == vertexCount else { continue }
            for index in 0 ..< vertexCount {
                positions[index] += target.deltas[index].position * weight
                normals[index] += target.deltas[index].normal * weight
            }
        }
        return zip(positions, normals).map(MorphVertexDelta.init)
    }

    private static func normals(
        vertices: [SIMD3<Float>],
        triangles: [TRITriangle]
    ) -> [SIMD3<Float>] {
        var sums = [SIMD3<Float>](repeating: .zero, count: vertices.count)
        for triangle in triangles {
            let a = Int(triangle.vertices.x)
            let b = Int(triangle.vertices.y)
            let third = Int(triangle.vertices.z)
            let normal = simd_cross(vertices[b] - vertices[a], vertices[third] - vertices[a])
            sums[a] += normal
            sums[b] += normal
            sums[third] += normal
        }
        return sums.map { simd_length_squared($0) > 0 ? simd_normalize($0) : .zero }
    }
}

nonisolated public final class FaceMorphBuffer {
    public let buffer: MTLBuffer
    public let vertexCount: Int
    public let targets: [FaceMorphTarget]
    public private(set) var currentDeltas: [MorphVertexDelta]

    public init(device: MTLDevice, tri: TRIFile, mesh: RenderMesh) throws {
        guard tri.baseVertices.count == mesh.vertexCount else {
            throw FaceMorphError.vertexCountMismatch(
                tri: tri.baseVertices.count, mesh: mesh.vertexCount
            )
        }
        vertexCount = mesh.vertexCount
        targets = FaceMorphComposer.targets(from: tri)
        currentDeltas = FaceMorphComposer.compose(
            targets: targets, weights: [:], vertexCount: vertexCount
        )
        let length = vertexCount * MorphVertexLayout.stride * Renderer.maxFramesInFlight
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw FaceMorphError.bufferAllocationFailed
        }
        self.buffer = buffer
        buffer.label = "\(mesh.name ?? "face").morph-deltas"
        for slot in 0 ..< Renderer.maxFramesInFlight {
            prepare(slot: slot)
        }
    }

    public func update(weights: [String: Float]) {
        currentDeltas = FaceMorphComposer.compose(
            targets: targets, weights: weights, vertexCount: vertexCount
        )
    }

    public func prepare(slot: Int) {
        buffer.contents().advanced(by: byteOffset(slot: slot)).copyMemory(
            from: currentDeltas,
            byteCount: vertexCount * MorphVertexLayout.stride
        )
    }

    public func byteOffset(slot: Int) -> Int {
        slot * vertexCount * MorphVertexLayout.stride
    }
}
