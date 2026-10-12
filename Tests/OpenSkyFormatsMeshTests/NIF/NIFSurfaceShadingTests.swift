// Which lit-surface terms a BSLightingShaderProperty turns on, from its shader
// type, flags, and texture slots (docs/formats/nif-materials.md).

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFSurfaceShadingTests {
    private func shading(
        type: UInt32, flags1: UInt32, flags2: UInt32, slots: [Int: String], tail: [Float] = [0.3, 2]
    ) throws -> SurfaceShading {
        var paths = Array(repeating: "", count: 8)
        for (slot, path) in slots {
            paths[slot] = path
        }
        var tailData = Data()
        tail.forEach { tailData.appendFloat32($0) }
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSTriShape", NIFFixture.staticTriangleShape(shaderPropertyRef: 1)),
            .init("BSLightingShaderProperty", NIFFixture.bsLightingShaderProperty(
                shaderType: type, shaderFlags1: flags1, shaderFlags2: flags2,
                textureSetRef: 2, tail: tailData
            )),
            .init("BSShaderTextureSet", NIFFixture.bsShaderTextureSet(paths: paths))
        ]))
        return try #require(file.model().materials.first).shading
    }

    /// The flags of Ralof's FaceGen head on the real install.
    @Test func aFaceGenHeadUsesItsModelSpaceAndFaceTerms() throws {
        let head = try shading(type: 4, flags1: 0x8240_1703, flags2: 0x0200_8021, slots: [
            0: "head.dds", 1: "head_msn.dds", 2: "head_sk.dds", 3: "detail.dds",
            6: "tint.dds", 7: "head_s.dds"
        ], tail: [0.4, 10])
        #expect(head.terms == [
            .modelSpaceNormals, .specular, .specularMap, .emissive, .softLighting, .faceDetail
        ])
        #expect(head.glowTexture == "textures/head_sk.dds")
        #expect(head.detailTexture == "textures/detail.dds")
        #expect(head.backLightTexture == "textures/head_s.dds")
        #expect(head.lightingEffect1 == 0.4)
    }

    @Test func anEyeReflectsItsCubeMapThroughItsMask() throws {
        let eye = try shading(type: 16, flags1: 0x8242_0303, flags2: 0x0200_8081, slots: [
            0: "eye.dds", 4: "cubemaps/eyecube.dds", 5: "eyemask.dds"
        ], tail: [1, 10, 1.3])
        #expect(eye.terms.isSuperset(of: [.environment, .environmentMask]))
        #expect(eye.environmentTexture == "textures/cubemaps/eyecube.dds")
        #expect(eye.environmentScale == 1.3)
    }

    @Test func aGlowShapeScalesItsEmissiveColourByTheGlowMap() throws {
        let window = try shading(type: 2, flags1: 0xA240_0301, flags2: 0x8061, slots: [
            0: "window.dds", 2: "window_m.dds"
        ])
        #expect(window.terms == [.specular, .emissive, .glowMap])
        #expect(window.glowTexture == "textures/window_m.dds")
    }

    @Test func aTermWithAnEmptySlotStaysOff() throws {
        let bare = try shading(
            type: 2,
            flags1: 0x8040_0000,
            flags2: 0x0E00_0040,
            slots: [0: "a.dds"]
        )
        #expect(bare.terms == [.emissive])
        #expect(bare.textureKeys.isEmpty)
    }

    @Test func aHairShapeKeepsItsTintColour() throws {
        let hair = try shading(type: 6, flags1: 0x8244_030B, flags2: 0x0020_80A1, slots: [
            0: "hair.dds"
        ], tail: [0.3, 2, 0.635, 0.604, 0.447])
        #expect(hair.tintColor == SIMD3(0.635, 0.604, 0.447))
    }
}
