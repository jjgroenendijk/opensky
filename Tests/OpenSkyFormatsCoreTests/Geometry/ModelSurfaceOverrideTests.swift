// A head part's texture set and tint, and a base record's per-shape texture
// sets, laid over a synthetic model.

import Foundation
@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct ModelSurfaceOverrideTests {
    private static func model(colors: [SIMD4<Float>]) -> Model {
        let mesh = Mesh(
            name: "Hair", transform: matrix_identity_float4x4,
            positions: [.zero, SIMD3(1, 0, 0)], normals: [], tangents: [], bitangents: [],
            uvs: [], colors: colors, indices: [0, 1, 0], materialSlot: 0
        )
        let material = Material(
            diffuseTexture: "textures/old_d.dds", normalTexture: "textures/old_n.dds",
            uvOffset: .zero, uvScale: SIMD2(1, 1), alpha: 1, glossiness: 80,
            specularColor: SIMD3(1, 1, 1), specularStrength: 1, doubleSided: false,
            alphaBlend: false, alphaTestThreshold: 0.5
        )
        return Model(meshes: [mesh], materials: [material], skippedShapeCount: 0)
    }

    @Test func replacesTexturesAndMultipliesTheTintIntoVertexColors() {
        let surface = ModelSurfaceOverride(
            diffuseTexture: "textures/new_d.dds", normalTexture: nil, tint: SIMD3(0.5, 1, 0)
        )
        let result = surface.applied(to: Self.model(colors: [
            SIMD4(1, 1, 1, 1),
            SIMD4(0.5, 0.5, 0.5, 0.2)
        ]))
        #expect(result.materials.first?.diffuseTexture == "textures/new_d.dds")
        #expect(result.materials.first?.normalTexture == "textures/old_n.dds")
        #expect(result.materials.first?.alphaTestThreshold == 0.5)
        #expect(result.meshes.first?.colors == [SIMD4(0.5, 1, 0, 1), SIMD4(0.25, 0.5, 0, 0.2)])
    }

    @Test func aMeshWithoutColorsTakesTheTintAndAnEmptyOverrideKeysAlike() {
        let surface = ModelSurfaceOverride(
            diffuseTexture: nil,
            normalTexture: nil,
            tint: SIMD3(1, 0, 0)
        )
        let result = surface.applied(to: Self.model(colors: []))
        #expect(result.meshes.first?.colors == [SIMD4(1, 0, 0, 1), SIMD4(1, 0, 0, 1)])
        let empty = ModelSurfaceOverride(diffuseTexture: nil, normalTexture: nil, tint: nil)
        #expect(empty.isEmpty)
        #expect(surface.cacheKey != empty.cacheKey)
    }

    @Test func aShapeSwapRetexturesOnlyThatShape() {
        let base = Self.model(colors: [])
        let other = base.meshes[0]
        let rock = Mesh(
            name: "Rock", transform: other.transform, positions: other.positions,
            normals: [], tangents: [], bitangents: [], uvs: [], colors: [],
            indices: other.indices, materialSlot: 0
        )
        let model = Model(meshes: [other, rock], materials: base.materials, skippedShapeCount: 0)
        let surface = ModelSurfaceOverride(
            diffuseTexture: nil, normalTexture: nil, tint: nil,
            shapes: [ModelSurfaceOverride.ShapeTextures(
                shapeName: "rock", diffuseTexture: "textures/grass_d.dds", normalTexture: nil
            )]
        )
        let result = surface.applied(to: model)
        #expect(result.meshes.map(\.materialSlot) == [0, 1])
        #expect(result.materials.map(\.diffuseTexture) == [
            "textures/old_d.dds", "textures/grass_d.dds"
        ])
        #expect(result.materials.last?.normalTexture == "textures/old_n.dds")
        #expect(!surface.isEmpty)
        let plain = ModelSurfaceOverride(diffuseTexture: nil, normalTexture: nil, tint: nil)
        #expect(surface.cacheKey != plain.cacheKey)
    }
}
