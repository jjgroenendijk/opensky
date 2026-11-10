// Effect scene walk over synthetic in-code files (NIFFixture); docs/formats/nif.md.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct NIFEffectSceneTests {
    @Test func aShadedShapeKeepsItsBlendAlphaTestAndShaderBlock() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1])),
            .init("BSTriShape", NIFFixture.staticTriangleShape(
                shaderPropertyRef: 2, alphaPropertyRef: 3
            )),
            .init("BSEffectShaderProperty", NIFParticleFixture.effectShaderProperty(
                sourceTexture: "textures\\effects\\glow.dds"
            )),
            // SRC_ALPHA / INV_SRC_ALPHA blending, with the alpha test on.
            .init("NiAlphaProperty", NIFFixture.niAlphaProperty(flags: 0x2ED, threshold: 128))
        ]))
        let scene = try NIFEffectScene(file: file)
        #expect(scene.nodes.count == 2, "the root and the shape's own node")
        let shape = try #require(scene.shapes.first)
        #expect(scene.shapes.count == 1)
        #expect(shape.node == 1)
        #expect(shape.shaderBlock == 2)
        #expect(shape.indices == [0, 1, 2])
        #expect(shape.colors == Array(repeating: .one, count: 3), "no vertex colours reads white")
        #expect(shape.material.blend == NIFBlend(source: 6, destination: 7))
        #expect(shape.material.alphaTest == Float(128) / 255)
        #expect(shape.material.sourceTexture != nil)
    }

    @Test func aShapeWithoutAShaderIsANodeOnly() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1])),
            .init("BSTriShape", NIFFixture.staticTriangleShape())
        ]))
        let scene = try NIFEffectScene(file: file)
        #expect(scene.nodes.count == 2)
        #expect(scene.shapes.isEmpty)
    }
}
