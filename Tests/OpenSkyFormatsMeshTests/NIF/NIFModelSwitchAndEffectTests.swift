// Scene-graph flatten of selector nodes and effect shapes. Synthetic in-code
// files only (NIFFixture); docs/formats/nif.md.

import FormatsTesting
import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct NIFModelSwitchAndEffectTests {
    private func shape(shaderPropertyRef: Int32 = -1, alphaPropertyRef: Int32 = -1) -> Data {
        NIFFixture.staticTriangleShape(
            shaderPropertyRef: shaderPropertyRef,
            alphaPropertyRef: alphaPropertyRef
        )
    }

    @Test func switchNodeDrawsOnlyItsActiveChild() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1])),
            .init("NiSwitchNode", NIFFixture.niSwitchNode(children: [2, 3], activeIndex: 1)),
            .init("BSTriShape", shape()),
            .init("NiNode", NIFFixture.niNode(children: [4, 5])),
            .init("BSTriShape", shape()),
            .init("BSTriShape", shape())
        ]))
        #expect(try file.model().meshes.count == 2)
    }

    @Test func switchNodeIndexPastItsChildrenDrawsNothing() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiSwitchNode", NIFFixture.niSwitchNode(children: [1], activeIndex: 4)),
            .init("BSTriShape", shape())
        ]))
        #expect(try file.model().meshes.isEmpty)
    }

    @Test func waterShaderShapeGetsTheWaterSurfaceMaterial() throws {
        // The block body is not decoded: the cell's WATR gives the look.
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1])),
            .init("BSTriShape", shape(shaderPropertyRef: 2)),
            .init("BSWaterShaderProperty", Data(count: 16))
        ]))
        let model = try file.model()
        #expect(model.meshes.count == 1)
        #expect(model.materials[0] == .waterSurface)
        #expect(model.materials[0].waterSurface)
    }

    @Test func effectShapeDrawsItsSourceTextureBlended() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 2, 3])),
            .init("BSTriShape", shape(shaderPropertyRef: 4, alphaPropertyRef: 6)),
            .init("BSTriShape", shape(shaderPropertyRef: 5)),
            .init("BSTriShape", shape(shaderPropertyRef: 4, alphaPropertyRef: 7)),
            .init("BSEffectShaderProperty", NIFParticleFixture.effectShaderProperty(
                flags2: 0x10,
                sourceTexture: "textures\\effects\\cloudtile.dds"
            )),
            .init("BSEffectShaderProperty", NIFParticleFixture.effectShaderProperty()),
            // SRC_ALPHA / INV_SRC_ALPHA, then SRC_ALPHA / ONE (additive).
            .init("NiAlphaProperty", NIFFixture.niAlphaProperty(flags: 0xED, threshold: 0)),
            .init("NiAlphaProperty", NIFFixture.niAlphaProperty(flags: 0x0D, threshold: 0))
        ]))
        let model = try file.model()
        #expect(model.meshes.count == 1)
        #expect(model.skippedShapeCount == 2)
        let material = model.materials[0]
        #expect(material.diffuseTexture == "textures/effects/cloudtile.dds")
        #expect(material.alphaBlend)
        #expect(material.doubleSided)
    }

    /// Particle emitter source meshes set the hidden bit; the game never draws them.
    @Test func hiddenShapesAndHiddenNodesDoNotDraw() throws {
        let hidden = NIFFixture.avObjectPrefix(flags: 0xF)
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 2, 3])),
            .init("BSTriShape", shape()),
            .init("BSTriShape", NIFFixture.staticTriangleShape(prefix: hidden)),
            .init("NiNode", NIFFixture.niNode(prefix: hidden, children: [4])),
            .init("BSTriShape", shape())
        ]))
        let model = try file.model()
        #expect(model.meshes.count == 1)
        #expect(model.skippedShapeCount == 1)
    }

    @Test func effectShapeCarriesItsUnlitShading() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSTriShape", shape(shaderPropertyRef: 1, alphaPropertyRef: 2)),
            // Flags 1: vertex alpha, palette color and alpha, falloff.
            // Flags 2: vertex colors.
            .init("BSEffectShaderProperty", NIFParticleFixture.effectShaderProperty(
                flags1: 0x78,
                flags2: 0x20,
                sourceTexture: "textures\\effects\\fxwhitewater01.dds",
                baseColor: SIMD4(0.5, 0.25, 1, 0.75),
                baseColorScale: 2,
                falloff: SIMD4(0.9, 0.1, 1, 0.2),
                greyscaleTexture: "textures\\effects\\gradients\\gradwhitewater.dds"
            )),
            .init("NiAlphaProperty", NIFFixture.niAlphaProperty(flags: 0xED, threshold: 0))
        ]))
        let effect = try #require(try file.model().materials.first?.effect)
        #expect(effect.baseColor == SIMD4(0.5, 0.25, 1, 0.75))
        #expect(effect.baseColorScale == 2)
        #expect(effect.paletteTexture == "textures/effects/gradients/gradwhitewater.dds")
        #expect(effect.paletteColor && effect.paletteAlpha)
        #expect(effect.falloff == SIMD4(0.9, 0.1, 1, 0.2))
        #expect(effect.vertexColors && effect.vertexAlpha)
    }

    /// A fire's heat-haze dome sets SLSF1 bit 15. With no refraction pass it would
    /// draw its normal map as colour, so it is skipped.
    @Test func refractionShapeIsSkipped() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 2])),
            .init("BSTriShape", shape(shaderPropertyRef: 3)),
            .init("BSTriShape", shape(shaderPropertyRef: 4)),
            .init(
                "BSLightingShaderProperty",
                NIFFixture.bsLightingShaderProperty(shaderFlags1: 0x8241_8309)
            ),
            .init("BSLightingShaderProperty", NIFFixture.bsLightingShaderProperty())
        ]))
        let model = try file.model()
        #expect(model.meshes.count == 1)
        #expect(model.skippedShapeCount == 1)
    }

    @Test func litShapeHasNoEffectShading() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSTriShape", shape())
        ]))
        #expect(try file.model().materials.first?.effect == nil)
    }
}
