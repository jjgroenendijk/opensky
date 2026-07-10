// Static-mesh vertex interleave + GPU buffer upload tests over synthetic
// meshes built in code. GPU tests skip when no Metal device (CI).

import Foundation
import Metal
@testable import opensky
import simd
import Testing

struct RenderMeshTests {
    private static let device = MTLCreateSystemDefaultDevice()

    private static var hasDevice: Bool {
        device != nil
    }

    private static func fullMesh() -> Mesh {
        Mesh(
            name: "full",
            transform: matrix_identity_float4x4,
            positions: [SIMD3(1, 2, 3), SIMD3(4, 5, 6)],
            normals: [SIMD3(0, 0, 1), SIMD3(1, 0, 0)],
            tangents: [],
            bitangents: [],
            uvs: [SIMD2(0.25, 0.5), SIMD2(0.75, 1)],
            colors: [SIMD4(1, 0, 0, 1), SIMD4(0, 1, 0, 0.5)],
            indices: [0, 1, 0],
            materialSlot: 0
        )
    }

    private static func bareMesh(indices: [UInt16] = [0, 1, 0]) -> Mesh {
        Mesh(
            name: nil,
            transform: matrix_identity_float4x4,
            positions: [SIMD3(1, 2, 3), SIMD3(4, 5, 6)],
            normals: [],
            tangents: [],
            bitangents: [],
            uvs: [],
            colors: [],
            indices: indices,
            materialSlot: 0
        )
    }

    @Test func layoutConstantsAreTightlyPacked() {
        #expect(StaticVertexLayout.positionOffset == 0)
        #expect(StaticVertexLayout.normalOffset == 12)
        #expect(StaticVertexLayout.texcoordOffset == 24)
        #expect(StaticVertexLayout.colorOffset == 32)
        #expect(StaticVertexLayout.stride == 48)
    }

    @Test func vertexDescriptorMatchesLayoutConstants() throws {
        let descriptor = StaticVertexLayout.vertexDescriptor()
        let position = try #require(descriptor.attributes[VertexAttribute.position.rawValue])
        let normal = try #require(descriptor.attributes[VertexAttribute.normal.rawValue])
        let texcoord = try #require(descriptor.attributes[VertexAttribute.texcoord.rawValue])
        let color = try #require(descriptor.attributes[VertexAttribute.color.rawValue])

        #expect(position.format == .float3)
        #expect(position.offset == StaticVertexLayout.positionOffset)
        #expect(normal.format == .float3)
        #expect(normal.offset == StaticVertexLayout.normalOffset)
        #expect(texcoord.format == .float2)
        #expect(texcoord.offset == StaticVertexLayout.texcoordOffset)
        #expect(color.format == .float4)
        #expect(color.offset == StaticVertexLayout.colorOffset)
        let layout = try #require(descriptor.layouts[BufferIndex.vertices.rawValue])
        #expect(layout.stride == StaticVertexLayout.stride)
    }

    @Test func interleavesAllAttributes() {
        let floats = StaticVertexLayout.interleave(Self.fullMesh())
        #expect(floats == [
            1, 2, 3, 0, 0, 1, 0.25, 0.5, 1, 0, 0, 1,
            4, 5, 6, 1, 0, 0, 0.75, 1, 0, 1, 0, 0.5
        ])
    }

    @Test func missingAttributesGetNeutralDefaults() {
        let floats = StaticVertexLayout.interleave(Self.bareMesh())
        // +Z normal, origin UV, opaque white color.
        #expect(floats == [
            1, 2, 3, 0, 0, 1, 0, 0, 1, 1, 1, 1,
            4, 5, 6, 0, 0, 1, 0, 0, 1, 1, 1, 1
        ])
    }

    @Test(.enabled(if: Self.hasDevice)) func uploadsInterleavedBuffers() throws {
        let device = try #require(Self.device)
        let mesh = Self.fullMesh()
        let render = try RenderMesh(device: device, mesh: mesh)

        #expect(render.indexCount == 3)
        #expect(render.materialSlot == 0)

        let expectedVertices = StaticVertexLayout.interleave(mesh)
        let vertexBytes = Data(
            bytes: render.vertexBuffer.contents(),
            count: render.vertexBuffer.length
        )
        #expect(vertexBytes == expectedVertices.withUnsafeBytes { Data($0) })

        let indexBytes = Data(
            bytes: render.indexBuffer.contents(),
            count: render.indexBuffer.length
        )
        #expect(indexBytes == mesh.indices.withUnsafeBytes { Data($0) })
    }

    @Test(.enabled(if: Self.hasDevice)) func rejectsOutOfRangeIndex() throws {
        let device = try #require(Self.device)
        #expect(throws: RenderMeshError.indexOutOfRange(index: 7, vertexCount: 2)) {
            try RenderMesh(device: device, mesh: Self.bareMesh(indices: [0, 7, 1]))
        }
    }

    @Test(.enabled(if: Self.hasDevice)) func rejectsEmptyMesh() throws {
        let device = try #require(Self.device)
        #expect(throws: RenderMeshError.emptyMesh) {
            try RenderMesh(device: device, mesh: Self.bareMesh(indices: []))
        }
    }
}
