// The layout block of a cached model: it points at vertex and index bytes that equal what
// the renderer would build, and it marks the meshes that cannot load from them.

import Foundation
@testable import OpenSkyAssetCache
import OpenSkyFormatsCore
import simd
import Testing

struct ReadyModelLayoutTests {
    static func quad(name: String, offset: Float, vertices: Int = 4) -> Mesh {
        let positions = (0 ..< vertices).map { index in
            SIMD3<Float>(Float(index % 2) + offset, Float(index / 2), 0)
        }
        return Mesh(
            name: name, transform: MatrixMath.translation(SIMD3(offset, 0, 1)),
            positions: positions,
            normals: [SIMD3<Float>](repeating: SIMD3(0, 0, 1), count: vertices),
            tangents: [], bitangents: [],
            uvs: positions.map { SIMD2($0.x, $0.y) }, colors: [],
            indices: [0, 1, 3, 0, 3, 2], materialSlot: 0
        )
    }

    static var plainModel: Model {
        Model(
            meshes: [quad(name: "A", offset: 0), quad(name: "B", offset: 5)],
            materials: [.fallback], skippedShapeCount: 1, editorMarkerShapeCount: 2
        )
    }

    private func bytes(_ values: [some BitwiseCopyable]) -> Data {
        values.withUnsafeBytes { Data($0) }
    }

    @Test func theLayoutPointsAtTheInterleavedVerticesAndTheIndices() throws {
        let model = Self.plainModel
        let payload = ModelCacheCodec.encode(model)
        let layout = try ModelCacheCodec.decodeLayout(payload)
        #expect(layout.isReady)
        #expect(layout.materials == model.materials)
        #expect(layout.skippedShapeCount == 1)
        #expect(layout.editorMarkerShapeCount == 2)
        #expect(layout.bounds == ModelBounds.containing(model: model))
        for (ready, mesh) in zip(layout.meshes, model.meshes) {
            #expect(ready.name == mesh.name)
            #expect(ready.transform == mesh.transform)
            #expect(ready.vertexCount == 4)
            #expect(ready.indexCount == 6)
            #expect(ready.vertexRange.lowerBound % ModelCacheCodec.blockAlignment == 0)
            #expect(ready.indexRange.lowerBound % ModelCacheCodec.blockAlignment == 0)
            #expect(payload[ready.vertexRange] == bytes(InterleavedVertexLayout.interleave(mesh)))
            #expect(payload[ready.indexRange] == bytes(mesh.indices))
            #expect(ready.bounds == ModelBounds.containing(mesh.positions))
            #expect(ready.uvPerUnit == MeshUVDensity.uvPerUnit(
                positions: mesh.positions, uvs: mesh.uvs, indices: mesh.indices
            ))
        }
        #expect(ModelCacheCodec.layoutByteCount(head: payload.prefix(8)) ?? 0 < payload.count)
        let head = payload.prefix(ModelCacheCodec.layoutByteCount(head: payload) ?? 0)
        #expect(try ModelCacheCodec.decodeLayout(head) == layout)
    }

    @Test func skinnedAndBrokenMeshesAreNotReady() throws {
        var broken = Self.quad(name: "Broken", offset: 0)
        broken = Mesh(
            name: broken.name, transform: broken.transform, positions: broken.positions,
            normals: broken.normals, tangents: [], bitangents: [], uvs: broken.uvs, colors: [],
            indices: [0, 1, 9], materialSlot: 0
        )
        let skinned = Mesh(
            name: "Skin", transform: matrix_identity_float4x4,
            positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)], normals: [],
            tangents: [], bitangents: [], uvs: [], colors: [], indices: [0, 1, 2],
            materialSlot: 0,
            skinning: MeshSkinning(
                weights: [SIMD4<Float>](repeating: SIMD4(1, 0, 0, 0), count: 3),
                boneIndices: [SIMD4<UInt16>](repeating: .zero, count: 3),
                bindPoseMatrices: [matrix_identity_float4x4], boneNames: ["Root"],
                rootParentToSkin: matrix_identity_float4x4,
                skinToBoneMatrices: [matrix_identity_float4x4]
            )
        )
        for mesh in [broken, skinned] {
            let model = Model(meshes: [mesh], materials: [.fallback], skippedShapeCount: 0)
            let layout = try ModelCacheCodec.decodeLayout(ModelCacheCodec.encode(model))
            #expect(!layout.isReady)
        }
        let empty = Model(meshes: [], materials: [], skippedShapeCount: 0)
        let emptyLayout = try ModelCacheCodec.decodeLayout(ModelCacheCodec.encode(empty))
        #expect(!emptyLayout.isReady)
    }

    @Test func aHeadWithoutTheWholeLayoutThrows() {
        let payload = ModelCacheCodec.encode(Self.plainModel)
        #expect(throws: CachePayloadError.self) {
            try ModelCacheCodec.decodeLayout(payload.prefix(20))
        }
    }
}
