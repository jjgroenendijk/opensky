// The lighting shader flags that change how a shape draws rather than how it is lit:
// depth, decal, shadows, distant LOD, screen door, and the vertex colour and alpha
// flags (docs/formats/nif-materials.md, "Draw state").

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct NIFShaderDrawStateTests {
    private func material(type: UInt32 = 0, flags1: UInt32, flags2: UInt32) throws -> Material {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSTriShape", NIFFixture.staticTriangleShape(shaderPropertyRef: 1)),
            .init("BSLightingShaderProperty", NIFFixture.bsLightingShaderProperty(
                shaderType: type, shaderFlags1: flags1, shaderFlags2: flags2
            ))
        ]))
        return try #require(file.model().materials.first)
    }

    /// The flags of Ralof's FaceGen head on the real install.
    @Test func aPlainShapeTestsAndWritesDepthAndTakesPartInShadows() throws {
        let state = try material(type: 4, flags1: 0x8240_1703, flags2: 0x0200_8021).drawState
        #expect(state == .standard)
    }

    @Test func clearedDepthBitsTurnTheTestAndTheWriteOff() throws {
        let state = try material(flags1: 0x0240_0301, flags2: 0x8020).drawState
        #expect(!state.depthTest)
        #expect(!state.depthWrite)
    }

    @Test func aDecalOrDynamicDecalPullsTowardTheEye() throws {
        #expect(try material(flags1: 0x8440_0301, flags2: 0x8021).drawState.decal)
        #expect(try material(flags1: 0x8840_0301, flags2: 0x8021).drawState.decal)
    }

    @Test func shadowBitsDecideCastingAndReceiving() throws {
        let none = try material(flags1: 0x8040_0001, flags2: 0x8021).drawState
        #expect(!none.castsShadows)
        #expect(!none.receivesShadows)
        let masked = try material(flags1: 0x8040_0001, flags2: 0x80A1).drawState
        #expect(masked.receivesShadows)
    }

    @Test func distantLODCastsAndReceivesNoShadow() throws {
        for flags2: UInt32 in [0x8023, 0x8025, 0x8000_8021] {
            let state = try material(type: 18, flags1: 0x8040_0301, flags2: flags2).drawState
            #expect(state.distantLOD)
            #expect(!state.castsShadows)
            #expect(!state.receivesShadows)
        }
    }

    @Test func screenDoorFadeIsADither() throws {
        #expect(try material(flags1: 0x8048_0301, flags2: 0x8021).drawState.screenDoor)
    }

    @Test func vertexAlphaAndColourCountOnlyWithTheirFlags() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 2])),
            .init("BSTriShape", NIFModelSwitchAndEffectTests.colouredShape(
                shaderPropertyRef: 3, alpha: 51, rgb: 128
            )),
            .init("BSTriShape", NIFModelSwitchAndEffectTests.colouredShape(
                shaderPropertyRef: 4, alpha: 51, rgb: 128
            )),
            .init("BSLightingShaderProperty", NIFFixture.bsLightingShaderProperty(
                shaderFlags1: 0x8040_0300, shaderFlags2: 0x8001
            )),
            .init("BSLightingShaderProperty", NIFFixture.bsLightingShaderProperty(
                shaderFlags1: 0x8040_0308, shaderFlags2: 0x8021
            ))
        ]))
        let meshes = try file.model().meshes
        #expect(meshes[0].colors.allSatisfy { $0 == SIMD4(1, 1, 1, 1) })
        #expect(meshes[1].colors.allSatisfy { abs($0.x - 0.5) < 0.01 && abs($0.w - 0.2) < 0.01 })
    }

    @Test func effectShapesReadTheirDepthAndDecalBits() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSTriShape", NIFFixture.staticTriangleShape(shaderPropertyRef: 1)),
            .init("BSEffectShaderProperty", NIFParticleFixture.effectShaderProperty(
                flags1: 0x0400_0000, sourceTexture: "fx.dds"
            ))
        ]))
        let state = try #require(file.model().materials.first).drawState
        #expect(!state.depthTest)
        #expect(!state.depthWrite)
        #expect(state.decal)
    }
}
