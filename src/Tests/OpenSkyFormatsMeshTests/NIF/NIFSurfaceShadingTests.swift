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
        #expect(window.terms == [.specular, .emissive, .glowMap, .externalEmittance])
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

    @Test func faceDetailNeedsTheFaceGenDetailFlag() throws {
        let head = try shading(type: 4, flags1: 0x8240_1303, flags2: 0x0200_8021, slots: [
            0: "head.dds", 3: "detail.dds"
        ])
        #expect(!head.terms.contains(.faceDetail))
        #expect(head.detailTexture == nil)
    }

    /// The flags of a hair shape on the real install.
    @Test func hairGetsSoftCappedAndStrandLighting() throws {
        let hair = try shading(type: 6, flags1: 0x8244_030B, flags2: 0x0020_80A1, slots: [
            0: "hair.dds"
        ], tail: [0.3, 2, 0.635, 0.604, 0.447])
        #expect(hair.terms.isSuperset(of: [.hairSoftLighting, .anisotropicLighting]))
    }

    @Test func aReflectionFadesWithLightOnlyWithItsFlag() throws {
        let slots = [0: "metal.dds", 4: "cubemaps/shiny.dds"]
        let lit = try shading(type: 1, flags1: 0x8040_0381, flags2: 0x8021, slots: slots)
        let unlit = try shading(type: 1, flags1: 0x8040_0381, flags2: 0x0021, slots: slots)
        #expect(lit.terms.contains(.environmentLightFade))
        #expect(unlit.terms.contains(.environment))
        #expect(!unlit.terms.contains(.environmentLightFade))
    }

    @Test func aWindowWithExternalEmittanceTakesItsReferenceColour() throws {
        let window = try shading(type: 2, flags1: 0xA200_0301, flags2: 0x8061, slots: [
            0: "window.dds", 2: "window_g.dds"
        ])
        #expect(window.terms.isSuperset(of: [.externalEmittance, .glowMap]))
    }

    @Test func sparkleSnowKeepsItsFourParameters() throws {
        let ice = try shading(type: 14, flags1: 0x8240_0301, flags2: 0x1000_0001, slots: [
            0: "ice.dds"
        ], tail: [0.3, 2, 7.2, 150, 1.2, 1.1])
        #expect(ice.terms.contains(.sparkle))
        #expect(ice.sparkle == SIMD4(7.2, 150, 1.2, 1.1))
    }

    @Test func distantLandUsesTheTerrainNoise() throws {
        let land = try shading(type: 18, flags1: 0x8000_0000, flags2: 0x0000_0003, slots: [
            0: "land.dds"
        ])
        #expect(land.terms.contains(.landscapeNoise))
        #expect(land.detailTexture == "textures/terrain/noise.dds")
    }
}
