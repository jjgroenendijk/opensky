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
}
