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
    case emptyMesh
    case bufferAllocationFailed
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

/// One mesh's GPU residence: interleaved vertex buffer + uint16 index
/// buffer, plus the mesh-local -> model-root transform and material slot
/// carried over from the engine Mesh.
nonisolated final class RenderMesh {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int
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
        localTransform = mesh.transform
        materialSlot = mesh.materialSlot
    }
}
