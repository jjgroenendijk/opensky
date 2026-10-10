// Scene-graph flatten of selector nodes and effect shapes. Synthetic in-code
// files only (NIFFixture); docs/formats/nif.md.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
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

    /// Tree branches carry wind weight in vertex alpha; it must not cut them away.
    @Test func treeAnimatedShapeIgnoresVertexAlpha() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 2])),
            .init("BSTriShape", Self.colouredShape(shaderPropertyRef: 3, alpha: 51)),
            .init("BSTriShape", Self.colouredShape(shaderPropertyRef: 4, alpha: 51)),
            .init(
                "BSLightingShaderProperty",
                NIFFixture.bsLightingShaderProperty(
                    shaderFlags1: 0x8040_0308, shaderFlags2: 0x2200_8031
                )
            ),
            .init(
                "BSLightingShaderProperty",
                NIFFixture.bsLightingShaderProperty(shaderFlags1: 0x8040_0308)
            )
        ]))
        let meshes = try file.model().meshes
        #expect(meshes.count == 2)
        #expect(meshes[0].colors.allSatisfy { $0.w == 1 })
        #expect(meshes[1].colors.allSatisfy { abs($0.w - 0.2) < 0.01 })
    }

    @Test func litShapeHasNoEffectShading() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSTriShape", shape())
        ]))
        #expect(try file.model().materials.first?.effect == nil)
    }
}

extension NIFModelSwitchAndEffectTests {
    /// The static triangle with an RGBA vertex colour after the tangent.
    static func colouredShape(shaderPropertyRef: Int32, alpha: UInt8) -> Data {
        var record = Data()
        record.appendFloat32(1)
        record.appendFloat32(2)
        record.appendFloat32(3)
        record.appendFloat32(0)
        record.appendFloat16(0)
        record.appendFloat16(0)
        record.append(contentsOf: [128, 128, 255, 128])
        record.append(contentsOf: [255, 128, 128, 128])
        record.append(contentsOf: [255, 255, 255, alpha])
        return NIFFixture.bsTriShape(
            shaderPropertyRef: shaderPropertyRef,
            attributes: 0x3B,
            strideDwords: 8,
            vertexRecords: Array(repeating: record, count: 3),
            triangles: [0, 1, 2]
        )
    }
}
