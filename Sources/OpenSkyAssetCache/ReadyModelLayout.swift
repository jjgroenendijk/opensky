// The layout block at the start of a cached model: what a loader needs to make GPU meshes
// without reading the model's arrays, and where each mesh's ready bytes lie.

import Foundation
import OpenSkyFormatsCore
import simd

/// One mesh of a cached model. Its byte ranges count from the start of the payload.
nonisolated public struct ReadyMeshLayout: Equatable, Sendable {
    public let name: String?
    public let transform: float4x4
    public let materialSlot: Int
    public let vertexCount: Int
    public let indexCount: Int
    /// Nil for a mesh with no vertex.
    public let bounds: ModelBounds?
    public let uvPerUnit: Float
    /// False for a skinned mesh, an empty one, or one whose indices pass its vertices.
    /// Such a model loads through the whole decode, which reports the problem.
    public let isReady: Bool
    /// `InterleavedVertexLayout` vertices.
    public let vertexRange: Range<Int>
    /// uint16 indices.
    public let indexRange: Range<Int>
}

nonisolated public struct ReadyModelLayout: Equatable, Sendable {
    public let materials: [Material]
    public let skippedShapeCount: Int
    public let editorMarkerShapeCount: Int
    public let meshes: [ReadyMeshLayout]
    /// Where the whole model lies in the payload.
    public let modelRange: Range<Int>

    /// True when every mesh can load from its ready bytes.
    public var isReady: Bool {
        !meshes.isEmpty && meshes.allSatisfy(\.isReady)
    }

    /// The union of each mesh's bounds in model space, like `ModelBounds.containing(model:)`.
    public var bounds: ModelBounds? {
        meshes.compactMap { mesh in mesh.bounds?.transformed(by: mesh.transform) }
            .reduce(nil) { result, next in result.map { $0.union(next) } ?? next }
    }
}

struct ReadyMeshRanges {
    let vertices: Range<Int>
    let indices: Range<Int>
}

nonisolated enum ReadyModelLayoutCodec {
    /// `ranges` and `modelRange` count from the first byte after the layout block.
    static func encode(_ model: Model, ranges: [ReadyMeshRanges], modelRange: Range<Int>) -> Data {
        var out = CachePayloadWriter()
        out.int(model.skippedShapeCount)
        out.int(model.editorMarkerShapeCount)
        out.int(model.materials.count)
        model.materials.forEach { ModelCacheCodec.encode($0, into: &out) }
        out.int(modelRange.lowerBound)
        out.int(modelRange.count)
        out.int(model.meshes.count)
        for (mesh, range) in zip(model.meshes, ranges) {
            encode(mesh, ranges: range, into: &out)
        }
        return out.data
    }

    /// `dataStart` is the payload offset of the first byte after the layout block.
    static func decode(_ data: Data, dataStart: Int) throws -> ReadyModelLayout {
        var input = CachePayloadReader(data)
        let skipped = try input.int()
        let markers = try input.int()
        let materials = try (0 ..< ModelCacheCodec.count(input.int(), in: data))
            .map { _ in try ModelCacheCodec.material(&input) }
        let modelRange = try range(&input, from: dataStart)
        let meshes = try (0 ..< ModelCacheCodec.count(input.int(), in: data))
            .map { _ in try mesh(&input, dataStart: dataStart) }
        guard input.isAtEnd else { throw CachePayloadError.truncated }
        return ReadyModelLayout(
            materials: materials, skippedShapeCount: skipped, editorMarkerShapeCount: markers,
            meshes: meshes, modelRange: modelRange
        )
    }

    private static func encode(
        _ mesh: Mesh, ranges: ReadyMeshRanges, into out: inout CachePayloadWriter
    ) {
        let bounds = ModelBounds.containing(mesh.positions)
        let ready = mesh.skinning == nil && bounds != nil && !mesh.indices.isEmpty
            && mesh.indices.allSatisfy { Int($0) < mesh.positions.count }
        out.string(mesh.name)
        out.value(mesh.transform)
        out.int(mesh.materialSlot)
        out.int(mesh.positions.count)
        out.int(mesh.indices.count)
        out.array(bounds.map { [$0.min, $0.max] } ?? [])
        out.value(MeshUVDensity.uvPerUnit(
            positions: mesh.positions, uvs: mesh.uvs, indices: mesh.indices
        ))
        out.bool(ready)
        out.int(ranges.vertices.lowerBound)
        out.int(ranges.vertices.count)
        out.int(ranges.indices.lowerBound)
        out.int(ranges.indices.count)
    }

    private static func mesh(
        _ input: inout CachePayloadReader, dataStart: Int
    ) throws -> ReadyMeshLayout {
        let name = try input.string()
        let transform = try input.value(float4x4.self)
        let slot = try input.int()
        let vertexCount = try input.int()
        let indexCount = try input.int()
        let corners = try input.array(SIMD3<Float>.self)
        let uvPerUnit = try input.value(Float.self)
        let ready = try input.bool()
        let vertices = try range(&input, from: dataStart)
        let indices = try range(&input, from: dataStart)
        let expected = (
            vertexCount * InterleavedVertexLayout.stride,
            indexCount * MemoryLayout<UInt16>.stride
        )
        guard
            vertexCount >= 0, indexCount >= 0, vertices.count == expected.0,
            indices.count == expected.1, corners.isEmpty || corners.count == 2
        else { throw CachePayloadError.badCount(vertexCount) }
        return ReadyMeshLayout(
            name: name, transform: transform, materialSlot: slot, vertexCount: vertexCount,
            indexCount: indexCount,
            bounds: corners.count == 2 ? ModelBounds(min: corners[0], max: corners[1]) : nil,
            uvPerUnit: uvPerUnit, isReady: ready, vertexRange: vertices, indexRange: indices
        )
    }

    private static func range(_ input: inout CachePayloadReader, from start: Int) throws
        -> Range<Int>
    {
        let offset = try input.int()
        let count = try input.int()
        guard offset >= 0, count >= 0, offset <= Int(Int32.max), count <= Int(Int32.max) else {
            throw CachePayloadError.badCount(count)
        }
        return (start + offset) ..< (start + offset + count)
    }
}
