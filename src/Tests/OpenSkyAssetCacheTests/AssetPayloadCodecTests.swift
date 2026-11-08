// The converted payloads decode to exactly what the direct load path builds:
// flattened models.

import Foundation
@testable import OpenSkyAssetCache
import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import simd
import Testing

struct AssetPayloadCodecTests {
    private func bytes(_ values: [some Any]) -> Data {
        values.withUnsafeBytes { unsafe Data($0) }
    }

    private var skinnedModel: Model {
        let skinning = MeshSkinning(
            weights: [SIMD4(0.5, 0.5, 0, 0), SIMD4(1, 0, 0, 0), SIMD4(0.25, 0.75, 0, 0)],
            boneIndices: [SIMD4(0, 1, 0, 0), SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0)],
            bindPoseMatrices: [matrix_identity_float4x4, MatrixMath.translation(SIMD3(1, 2, 3))],
            boneNames: ["NPC Root [Root]", "NPC Spine"],
            rootParentToSkin: MatrixMath.translation(SIMD3(0, 0, 9)),
            skinToBoneMatrices: [matrix_identity_float4x4],
            bodyParts: [MeshBodyPart(bodyPart: 32, indices: 0 ..< 3)]
        )
        let mesh = Mesh(
            name: "Body", transform: MatrixMath.translation(SIMD3(4, 5, 6)),
            positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0.1)],
            normals: [SIMD3(0, 0, 1), SIMD3(0, 0, 1), SIMD3(0, 0, 1)],
            tangents: [], bitangents: [],
            uvs: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1)],
            colors: [SIMD4(1, 0.5, 0.25, 1), SIMD4(1, 1, 1, 1), SIMD4(0, 0, 0, 1)],
            indices: [0, 1, 2], materialSlot: 1, skinning: skinning
        )
        let plain = Mesh(
            name: nil, transform: matrix_identity_float4x4, positions: [SIMD3(9, 9, 9)],
            normals: [], tangents: [SIMD3(1, 0, 0)], bitangents: [SIMD3(0, 1, 0)], uvs: [],
            colors: [], indices: [0, 0, 0], materialSlot: 0, objectLODSegment: 3
        )
        var shading = SurfaceShading()
        shading.terms = [.modelSpaceNormals, .softLighting, .environment]
        shading.emissiveColor = SIMD3(0.1, 0.2, 0.3)
        shading.lightingEffect1 = 0.4
        shading.tintColor = SIMD3(0.7, 0.6, 0.5)
        shading.multiLayer.innerScale = SIMD2(2, 3)
        shading.glowTexture = "textures/a_sk.dds"
        shading.environmentTexture = "textures/cubemaps/a.dds"
        shading.sparkle = SIMD4(7.2, 150, 1.2, 1.1)
        var drawState = MaterialDrawState()
        (drawState.depthWrite, drawState.decal, drawState.screenDoor) = (false, true, true)
        let cutout = Material(
            diffuseTexture: "textures\\a.dds", normalTexture: nil, uvOffset: SIMD2(0.5, 0),
            uvScale: SIMD2(2, 2), alpha: 0.75, glossiness: 30, specularColor: SIMD3(1, 0.5, 0),
            specularStrength: 2, doubleSided: true, alphaBlend: false, alphaTestThreshold: 0.5,
            tintTexture: "textures/facetint.dds", tintsSkin: true, shading: shading,
            drawState: drawState
        )
        let foam = Material(
            diffuseTexture: "textures/effects/foam.dds", normalTexture: nil, uvOffset: .zero,
            uvScale: SIMD2(1, 1), alpha: 1, glossiness: 80, specularColor: SIMD3(1, 1, 1),
            specularStrength: 0, doubleSided: true, alphaBlend: true, alphaTestThreshold: nil,
            additiveBlend: .one,
            effect: EffectShading(
                baseColor: SIMD4(1, 0.5, 0.25, 0.75), baseColorScale: 2,
                paletteTexture: "textures/effects/gradients/foam.dds", paletteColor: true,
                paletteAlpha: false, falloff: SIMD4(0.9, 0.1, 1, 0), vertexColors: true,
                vertexAlpha: false, softFalloffDepth: 32, lightingInfluence: 0.75,
                externalEmittance: true, weaponBlood: true
            )
        )
        return Model(
            meshes: [mesh, plain],
            materials: [.fallback, cutout, foam, .waterSurface],
            skippedShapeCount: 2,
            editorMarkerShapeCount: 1
        )
    }

    @Test func aModelDecodesToTheSameArraysAndMaterials() throws {
        let model = skinnedModel
        let decoded = try ModelCacheCodec.decode(ModelCacheCodec.encode(model))
        #expect(decoded.materials == model.materials)
        #expect(decoded.skippedShapeCount == 2)
        #expect(decoded.editorMarkerShapeCount == 1)
        #expect(decoded.meshes.count == model.meshes.count)
        for (left, right) in zip(decoded.meshes, model.meshes) {
            #expect(left.name == right.name)
            #expect(left.transform == right.transform)
            #expect(bytes(left.positions) == bytes(right.positions))
            #expect(bytes(left.normals) == bytes(right.normals))
            #expect(bytes(left.tangents) == bytes(right.tangents))
            #expect(bytes(left.bitangents) == bytes(right.bitangents))
            #expect(left.uvs == right.uvs)
            #expect(left.colors == right.colors)
            #expect(left.indices == right.indices)
            #expect(left.materialSlot == right.materialSlot)
            #expect(left.objectLODSegment == right.objectLODSegment)
            #expect(left.skinning?.weights == right.skinning?.weights)
            #expect(left.skinning?.boneIndices == right.skinning?.boneIndices)
            #expect(left.skinning?.bindPoseMatrices == right.skinning?.bindPoseMatrices)
            #expect(left.skinning?.boneNames == right.skinning?.boneNames)
            #expect(left.skinning?.rootParentToSkin == right.skinning?.rootParentToSkin)
            #expect(left.skinning?.skinToBoneMatrices == right.skinning?.skinToBoneMatrices)
            #expect(left.skinning?.bodyParts == right.skinning?.bodyParts)
        }
    }

    @Test func aTruncatedModelPayloadThrows() {
        let data = ModelCacheCodec.encode(skinnedModel)
        #expect(throws: CachePayloadError.self) {
            try ModelCacheCodec.decode(data.prefix(data.count - 3))
        }
    }
}
