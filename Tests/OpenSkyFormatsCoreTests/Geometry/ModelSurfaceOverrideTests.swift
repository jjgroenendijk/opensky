// A head part's texture set and tint laid over a synthetic model.

import Foundation
@testable import OpenSkyFormatsCore
import simd
import TagsTesting
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
}
