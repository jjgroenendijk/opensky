// Engine Mesh -> GPU buffers for the static-mesh pipeline (todo 2.6).
// Vertex data is interleaved into one buffer whose layout is defined once
// here (offsets + MTLVertexDescriptor) so Swift packing and the shader's
// stage_in view cannot drift apart. Missing attribute arrays get neutral
// defaults instead of failing — vanilla NIFs legitimately omit them.

import Foundation
import Metal
import simd

nonisolated enum RenderMeshError: Error, Equatable {
    /// Triangle index points past the vertex array (defensive: parsers
    /// validate, but this data ultimately comes from external files).
    case indexOutOfRange(index: UInt16, vertexCount: Int)
    case boneIndexOutOfRange(index: UInt16, boneCount: Int)
    case invalidSkinningData
    case emptyMesh
    case bufferAllocationFailed
}

/// Second stream for skinned meshes. Swift's SIMD alignment makes this 32
/// bytes (16-byte float4, 8-byte ushort4, tail padding); descriptor uses the
/// same MemoryLayout stride so CPU/GPU packing cannot drift.
nonisolated struct SkinVertex {
    let weights: SIMD4<Float>
    let boneIndices: SIMD4<UInt16>
}

nonisolated enum SkinVertexLayout {
    static let weightsOffset = 0
    static let boneIndicesOffset = 16
    static let stride = MemoryLayout<SkinVertex>.stride

    static func vertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = StaticVertexLayout.vertexDescriptor()
        let buffer = BufferIndex.skinningAttributes.rawValue
        descriptor.attributes[VertexAttribute.boneWeights.rawValue].format = .float4
        descriptor.attributes[VertexAttribute.boneWeights.rawValue].offset = weightsOffset
        descriptor.attributes[VertexAttribute.boneWeights.rawValue].bufferIndex = buffer
        descriptor.attributes[VertexAttribute.boneIndices.rawValue].format = .ushort4
        descriptor.attributes[VertexAttribute.boneIndices.rawValue].offset = boneIndicesOffset
        descriptor.attributes[VertexAttribute.boneIndices.rawValue].bufferIndex = buffer
        descriptor.layouts[buffer].stride = stride
        descriptor.layouts[buffer].stepRate = 1
        descriptor.layouts[buffer].stepFunction = .perVertex
        return descriptor
    }
}

/// Interleaved layout of one static-mesh vertex: float3 position, float3
/// normal, float2 texcoord, float4 color — 48 bytes, tightly packed floats
/// (not simd-aligned; the vertex descriptor below is the single source of
/// truth for the shader's view of it).
nonisolated enum StaticVertexLayout {
    static let positionOffset = 0
    static let normalOffset = 12
    static let texcoordOffset = 24
    static let colorOffset = 32
    static let stride = 48

    /// Attribute defaults for meshes that omit an array: +Z normal (world
    /// up, docs/decisions/coordinates.md), origin UV, opaque white color.
    static let defaultNormal = SIMD3<Float>(0, 0, 1)
    static let defaultColor = SIMD4<Float>(1, 1, 1, 1)

    static func vertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        let buffer = BufferIndex.vertices.rawValue

        func set(_ attribute: VertexAttribute, _ format: MTLVertexFormat, _ offset: Int) {
            descriptor.attributes[attribute.rawValue].format = format
            descriptor.attributes[attribute.rawValue].offset = offset
            descriptor.attributes[attribute.rawValue].bufferIndex = buffer
        }
        set(.position, .float3, positionOffset)
        set(.normal, .float3, normalOffset)
        set(.texcoord, .float2, texcoordOffset)
        set(.color, .float4, colorOffset)

        descriptor.layouts[buffer].stride = stride
        descriptor.layouts[buffer].stepRate = 1
        descriptor.layouts[buffer].stepFunction = .perVertex
        return descriptor
    }

    /// Packs a mesh's attribute arrays into the interleaved layout above.
    /// Mesh contract: attribute arrays are empty or vertex-count sized.
    static func interleave(_ mesh: Mesh) -> [Float] {
        var floats: [Float] = []
        floats.reserveCapacity(mesh.positions.count * stride / MemoryLayout<Float>.size)
        for index in mesh.positions.indices {
            let position = mesh.positions[index]
            let normal = index < mesh.normals.count ? mesh.normals[index] : defaultNormal
            let uv = index < mesh.uvs.count ? mesh.uvs[index] : .zero
            let color = index < mesh.colors.count ? mesh.colors[index] : defaultColor
            floats.append(contentsOf: [
                position.x, position.y, position.z,
                normal.x, normal.y, normal.z,
                uv.x, uv.y,
                color.x, color.y, color.z, color.w
            ])
        }
        return floats
    }
}

/// Terrain vertex layout: the static interleaved stream plus a second buffer
/// (BufferIndexTerrainWeights) carrying two float4 splat-weight lanes per
/// vertex — up to TerrainConstantMaxLayers (8) ATXT layer opacities. Kept as
/// a parallel stream instead of forking the 48-byte static layout so
/// RenderMesh upload and StaticVertexLayout stay untouched
/// (docs/rendering/metal4-renderer.md, terrain splat section).
nonisolated enum TerrainVertexLayout {
    /// Two tightly packed float4 lanes per vertex.
    static let weightsStride = 32

    static func vertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = StaticVertexLayout.vertexDescriptor()
        let buffer = BufferIndex.terrainWeights.rawValue

        func set(_ attribute: VertexAttribute, _ offset: Int) {
            descriptor.attributes[attribute.rawValue].format = .float4
            descriptor.attributes[attribute.rawValue].offset = offset
            descriptor.attributes[attribute.rawValue].bufferIndex = buffer
        }
        set(.layerWeights0, 0)
        set(.layerWeights1, 16)

        descriptor.layouts[buffer].stride = weightsStride
        descriptor.layouts[buffer].stepRate = 1
        descriptor.layouts[buffer].stepFunction = .perVertex
        return descriptor
    }
}

/// One mesh's GPU residence: interleaved vertex buffer + uint16 index
/// buffer, plus the mesh-local -> model-root transform and material slot
/// carried over from the engine Mesh.
nonisolated final class RenderMesh {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int
    let skinningBuffer: MTLBuffer?
    let boneMatrixBuffer: MTLBuffer?
    var isSkinned: Bool {
        skinningBuffer != nil
    }

    /// Mesh-local -> model-root transform (see Geometry/Mesh.swift).
    let localTransform: float4x4
    /// Index into the owning model's materials.
    let materialSlot: Int

    init(device: MTLDevice, mesh: Mesh) throws {
        guard !mesh.positions.isEmpty, !mesh.indices.isEmpty else {
            throw RenderMeshError.emptyMesh
        }
        if let bad = mesh.indices.first(where: { Int($0) >= mesh.positions.count }) {
            throw RenderMeshError.indexOutOfRange(
                index: bad,
                vertexCount: mesh.positions.count
            )
        }

        let vertices = StaticVertexLayout.interleave(mesh)
        let skinBuffers = try Self.makeSkinBuffers(device: device, mesh: mesh)
        guard
            let vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<Float>.size,
                options: .storageModeShared
            ),
            let indexBuffer = device.makeBuffer(
                bytes: mesh.indices,
                length: mesh.indices.count * MemoryLayout<UInt16>.size,
                options: .storageModeShared
            ) else { throw RenderMeshError.bufferAllocationFailed }
        vertexBuffer.label = "\(mesh.name ?? "mesh").vertices"
        indexBuffer.label = "\(mesh.name ?? "mesh").indices"

        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        indexCount = mesh.indices.count
        skinningBuffer = skinBuffers.attributes
        boneMatrixBuffer = skinBuffers.matrices
        localTransform = mesh.transform
        materialSlot = mesh.materialSlot
    }

    private static func makeSkinBuffers(
        device: MTLDevice,
        mesh: Mesh
    ) throws -> (attributes: MTLBuffer?, matrices: MTLBuffer?) {
        guard let skinning = mesh.skinning else { return (nil, nil) }
        guard
            skinning.weights.count == mesh.positions.count,
            skinning.boneIndices.count == mesh.positions.count,
            !skinning.bindPoseMatrices.isEmpty
        else { throw RenderMeshError.invalidSkinningData }
        let boneCount = skinning.bindPoseMatrices.count
        let allIndices = skinning.boneIndices.flatMap { [$0.x, $0.y, $0.z, $0.w] }
        if let index = allIndices.first(where: { Int($0) >= boneCount }) {
            throw RenderMeshError.boneIndexOutOfRange(
                index: index,
                boneCount: boneCount
            )
        }
        let vertices = zip(skinning.weights, skinning.boneIndices).map(SkinVertex.init)
        guard
            let attributes = device.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<SkinVertex>.stride,
                options: .storageModeShared
            ),
            let matrices = device.makeBuffer(
                bytes: skinning.bindPoseMatrices,
                length: skinning.bindPoseMatrices.count * MemoryLayout<float4x4>.stride,
                options: .storageModeShared
            )
        else { throw RenderMeshError.bufferAllocationFailed }
        attributes.label = "\(mesh.name ?? "mesh").skin-vertices"
        matrices.label = "\(mesh.name ?? "mesh").bind-pose-bones"
        return (attributes, matrices)
    }
}
