// Scene-graph flatten tests: transform accumulation down the parent chain,
// material slot dedup, skip rules, cycle/ref defense. Synthetic in-code
// files only (NIFFixture); docs/formats/nif.md "Scene graph -> engine mesh".

import Foundation
@testable import opensky
import simd
import Testing

struct NIFModelTests {
    private static let staticAttributes: UInt16 = 0x1B
    private static let staticStrideDwords = 7

    /// Minimal one-triangle static shape payload.
    private func shape(
        prefix: Data = NIFFixture.avObjectPrefix(),
        skinRef: Int32 = -1,
        shaderPropertyRef: Int32 = -1,
        alphaPropertyRef: Int32 = -1,
        vertexCount: Int = 3
    ) -> Data {
        var record = Data()
        record.appendFloat32(1)
        record.appendFloat32(2)
        record.appendFloat32(3)
        record.appendFloat32(0) // bitangent X
        record.appendFloat16(0)
        record.appendFloat16(0)
        record.append(contentsOf: [128, 128, 255, 128]) // normal + bitangent Y
        record.append(contentsOf: [255, 128, 128, 128]) // tangent + bitangent Z
        return NIFFixture.bsTriShape(
            prefix: prefix,
            skinRef: skinRef,
            shaderPropertyRef: shaderPropertyRef,
            alphaPropertyRef: alphaPropertyRef,
            attributes: Self.staticAttributes,
            strideDwords: Self.staticStrideDwords,
            vertexRecords: Array(repeating: record, count: vertexCount),
            triangles: [0, 1, 2]
        )
    }

    @Test func accumulatesTransformsDownTheParentChain() throws {
        // BSFadeNode(translate) -> NiNode(rotate Z) -> BSTriShape(scale):
        // mesh transform must equal the ordered product of the three locals.
        let theta = MatrixMath.radians(fromDegrees: 90)
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSFadeNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(translation: SIMD3(0, 0, 100)),
                children: [1]
            )),
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(rotationColumns: [
                    cosf(theta), sinf(theta), 0,
                    -sinf(theta), cosf(theta), 0,
                    0, 0, 1
                ]),
                children: [2]
            )),
            .init("BSTriShape", shape(
                prefix: NIFFixture.avObjectPrefix(scale: 2)
            ))
        ]))
        let model = try file.model()
        #expect(model.meshes.count == 1)
        let expected = MatrixMath.translation(SIMD3(0, 0, 100))
            * MatrixMath.rotationZ(radians: theta)
            * MatrixMath.scale(uniform: 2)
        let got = model.meshes[0].transform
        for column in 0 ..< 4 {
            #expect(simd_length(got[column] - expected[column]) < 1e-5)
        }
        #expect(model.meshes[0].positions.count == 3)
        #expect(model.skippedShapeCount == 0)
    }

    @Test func dedupsMaterialSlotsAcrossShapes() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 2, 3])),
            .init("BSTriShape", shape(shaderPropertyRef: 4, alphaPropertyRef: 5)),
            .init("BSTriShape", shape(shaderPropertyRef: 4, alphaPropertyRef: 5)),
            .init("BSTriShape", shape(shaderPropertyRef: 6)),
            .init(
                "BSLightingShaderProperty",
                NIFFixture.bsLightingShaderProperty(glossiness: 32)
            ),
            .init("NiAlphaProperty", NIFFixture.niAlphaProperty(flags: 4844, threshold: 128)),
            .init(
                "BSLightingShaderProperty",
                NIFFixture.bsLightingShaderProperty(glossiness: 64)
            )
        ]))
        let model = try file.model()
        #expect(model.meshes.count == 3)
        #expect(model.materials.count == 2)
        #expect(model.meshes[0].materialSlot == model.meshes[1].materialSlot)
        #expect(model.meshes[2].materialSlot != model.meshes[0].materialSlot)
        #expect(model.materials[model.meshes[0].materialSlot].glossiness == 32)
        #expect(model.materials[model.meshes[2].materialSlot].glossiness == 64)
    }

    @Test func resolvesMaterialFromPropertyBlocks() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSTriShape", shape(shaderPropertyRef: 1, alphaPropertyRef: 3)),
            .init(
                "BSLightingShaderProperty",
                NIFFixture.bsLightingShaderProperty(
                    shaderFlags2: 0x8031, // double-sided bit set
                    uvScale: SIMD2(2, 2),
                    textureSetRef: 2,
                    alpha: 0.5,
                    glossiness: 100,
                    specularStrength: 3
                )
            ),
            .init("BSShaderTextureSet", NIFFixture.bsShaderTextureSet(paths: [
                "Textures\\Plants\\Leaf01.dds", "plants\\leaf01_n.dds"
            ])),
            .init(
                "NiAlphaProperty",
                NIFFixture.niAlphaProperty(flags: 0x200 | 4 << 10, threshold: 64)
            )
        ]))
        let model = try file.model()
        #expect(model.materials.count == 1)
        let material = model.materials[0]
        #expect(material.diffuseTexture == "textures/plants/leaf01.dds")
        #expect(material.normalTexture == "textures/plants/leaf01_n.dds")
        #expect(material.uvScale == SIMD2(2, 2))
        #expect(material.alpha == 0.5)
        #expect(material.glossiness == 100)
        #expect(material.specularStrength == 3)
        #expect(material.doubleSided)
        #expect(!material.alphaBlend)
        let threshold = try #require(material.alphaTestThreshold)
        #expect(abs(threshold - 64.0 / 255) < 1e-6)
    }

    @Test func nonLightingShaderFallsBack() throws {
        // Effect shaders are legitimate content out of M2 scope — fallback
        // material, no throw.
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSTriShape", shape(shaderPropertyRef: 1)),
            .init("BSEffectShaderProperty", Data(count: 32))
        ]))
        let model = try file.model()
        #expect(model.materials == [.fallback])
    }

    @Test func shapeWithoutPropertiesGetsFallbackMaterial() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSTriShape", shape())
        ]))
        let model = try file.model()
        #expect(model.materials == [.fallback])
        #expect(model.meshes[0].materialSlot == 0)
    }

    @Test func outOfRangeShaderRefIsMalformed() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSTriShape", shape(shaderPropertyRef: 9))
        ]))
        #expect(throws: NIFError.self) {
            try file.model()
        }
    }

    @Test func skipsSkinnedShapesAndCountsThem() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 2])),
            .init("BSTriShape", shape(skinRef: 3)),
            .init("BSTriShape", shape())
        ]))
        let model = try file.model()
        #expect(model.meshes.count == 1)
        #expect(model.skippedShapeCount == 1)
    }

    @Test func ignoresNonDrawableLeavesAndSelectorNodes() throws {
        // Collision object and a selector node under the root: neither may
        // contribute meshes; the walk must not decode their payloads.
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 2, 3])),
            .init("bhkCollisionObject", Data(count: 12)),
            .init("NiSwitchNode", NIFFixture.niNode(children: [3])),
            .init("BSTriShape", shape())
        ]))
        let model = try file.model()
        #expect(model.meshes.count == 1)
        #expect(model.skippedShapeCount == 0)
    }

    @Test func outOfRangeChildRefIsMalformed() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [9]))
        ]))
        #expect(throws: NIFError.malformed("block ref 9 out of range (1 blocks)")) {
            try file.model()
        }
    }

    @Test func refCycleIsMalformed() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1])),
            .init("NiNode", NIFFixture.niNode(children: [0]))
        ]))
        #expect(throws: NIFError.self) {
            try file.model()
        }
    }

    @Test func absurdDepthIsMalformed() throws {
        // 70-node parent chain: deeper than any real asset, must throw
        // instead of recursing without bound.
        let blocks = (0 ..< 70).map { index in
            NIFFixture.Block("NiNode", NIFFixture.niNode(
                children: index < 69 ? [Int32(index + 1)] : []
            ))
        }
        let file = try NIFFile(data: NIFFixture.file(blocks: blocks))
        #expect(throws: NIFError.malformed("scene graph deeper than 64")) {
            try file.model()
        }
    }

    @Test func negativeRootsAndEmptyFilesYieldEmptyModels() throws {
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [.init("NiNode", NIFFixture.niNode())],
            roots: [-1]
        ))
        let model = try file.model()
        #expect(model.meshes.isEmpty)
        #expect(model.materials.isEmpty)
    }
}
