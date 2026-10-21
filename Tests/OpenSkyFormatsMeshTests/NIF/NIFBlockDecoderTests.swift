// NIFBlockDecoders: extra data, node kinds, controllers, interpolators, the sky
// shader, and multi-bounds over synthetic blocks (docs/formats/nif-extra-data.md).

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFBlockDecoderTests {
    private func decode(_ type: String, _ data: Data, strings: [String] = []) throws -> Any? {
        let file = try NIFFile(data: NIFFixture.file(blocks: [.init(type, data)], strings: strings))
        return try NIFBlockDecoders.decode(file.blocks[0], header: file.header)
    }

    @Test func decodesScalarExtraData() throws {
        let integer = try decode("NiIntegerExtraData", NIFBlockFixture.extraData(
            nameIndex: 0, NIFBlockFixture.uint32(7)
        ), strings: ["Count"])
        #expect(integer as? NIFExtraData == NIFExtraData(name: "Count", value: .integer(7)))
        let flags = try #require(decode("BSXFlags", NIFBlockFixture.extraData(
            NIFBlockFixture.uint32(0x13)
        )) as? NIFExtraData)
        #expect(flags.value == .flags([.animated, .havok, .addon]))
        let bound = try #require(decode("BSBound", NIFBlockFixture.extraData(
            NIFBlockFixture.floats([1, 2, 3, 4, 5, 6])
        )) as? NIFExtraData)
        #expect(bound.value == .bound(center: SIMD3(1, 2, 3), halfExtents: SIMD3(4, 5, 6)))
    }

    @Test func decodesListExtraData() throws {
        var strings = NIFBlockFixture.uint32(2)
        strings.append(NIFFixture.sizedString("a"))
        strings.append(NIFFixture.sizedString("bc"))
        let list = try #require(decode(
            "NiStringsExtraData", NIFBlockFixture.extraData(strings)
        ) as? NIFExtraData)
        #expect(list.value == .strings(["a", "bc"]))

        var bones = NIFBlockFixture.uint32(1)
        bones.append(NIFBlockFixture.uint32(250))
        bones.append(NIFBlockFixture.uint32(0))
        let lod = try #require(decode(
            "BSBoneLODExtraData", NIFBlockFixture.extraData(bones), strings: ["NPC Head"]
        ) as? NIFExtraData)
        #expect(lod.value == .boneLOD([NIFBoneLOD(distance: 250, boneName: "NPC Head")]))
    }

    @Test func decodesDecalPlacementVectors() throws {
        var payload = NIFBlockFixture.floats([0.5])
        payload.appendUInt16(1)
        payload.appendUInt16(1)
        payload.append(NIFBlockFixture.floats([1, 2, 3, 0, 0, 1]))
        let decal = try #require(decode(
            "BSDecalPlacementVectorExtraData", NIFBlockFixture.extraData(payload)
        ) as? NIFExtraData)
        #expect(decal.value == .decalPlacement(NIFDecalPlacement(
            value: 0.5, points: [SIMD3(1, 2, 3)], normals: [SIMD3(0, 0, 1)]
        )))
    }

    @Test func rootExtraDataGivesInventoryMarker() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init(
                "NiNode",
                NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(extraDataRefs: [1, 2]))
            ),
            .init("BSInvMarker", NIFBlockFixture.extraData(NIFBlockFixture.inventoryMarker(
                rotation: SIMD3(1571, 0, 0), zoom: 1.5
            ))),
            .init("BSXFlags", NIFBlockFixture.extraData(NIFBlockFixture.uint32(0x10)))
        ]))
        let marker = try #require(file.inventoryMarker)
        #expect(abs(marker.rotation.x - 1.571) < 1e-5)
        #expect(marker.zoom == 1.5)
        #expect(file.bsxFlags == .addon)
        let up = marker.orientation.act(SIMD3(0, 0, 1))
        #expect(simd_distance(up, SIMD3(0, 1, 0)) < 1e-3)
    }

    @Test func leftoverBytesThrow() {
        var data = NIFBlockFixture.extraData(NIFBlockFixture.uint32(1))
        data.append(0)
        #expect(throws: NIFError.self) { try decode("NiIntegerExtraData", data) }
    }

    @Test func decodesNodeKinds() throws {
        let value = try #require(decode(
            "BSValueNode", NIFBlockFixture.valueNode(value: 42)
        ) as? NIFValueNode)
        #expect(value.value == 42)

        var range = NIFFixture.niNode()
        range.append(contentsOf: [1, 3, 2])
        let stage = try #require(decode("BSDamageStage", range) as? NIFRangeNode)
        #expect(stage.contains(stage: 2))
        #expect(!stage.contains(stage: 4))

        var master = NIFFixture.niNode()
        master.appendUInt16(8)
        master.append(NIFBlockFixture.uint32(1))
        master.appendRef(3)
        let system = try #require(decode(
            "BSMasterParticleSystem",
            master
        ) as? NIFMasterParticleSystem)
        #expect(system.maxEmitterObjects == 8)
        #expect(system.particleSystemRefs == [3])
    }

    @Test func addOnNodesSkipHiddenSubtrees() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 2])),
            .init("BSValueNode", NIFBlockFixture.valueNode(
                prefix: NIFFixture.avObjectPrefix(nameIndex: 0, translation: SIMD3(0, 0, 10)),
                value: 5
            )),
            .init("BSValueNode", NIFBlockFixture.valueNode(
                prefix: NIFFixture.avObjectPrefix(flags: 0xF), value: 6
            ))
        ], strings: ["AddOnNode5"]))
        let nodes = try file.addOnNodes()
        #expect(nodes.map(\.index) == [5])
        #expect(nodes.first?.name == "AddOnNode5")
        #expect(nodes.first?.transform.columns.3 == SIMD4(0, 0, 10, 1))
    }

    @Test func decodesControllerBlocks() throws {
        var lag = NIFBlockFixture.timeController()
        lag.append(NIFBlockFixture.floats([1, 2, 30]))
        let bone = try #require(decode("BSLagBoneController", lag) as? NIFLagBoneController)
        #expect(bone.maximumDistance == 30)

        var shader = NIFBlockFixture.interpolatedController(interpolator: 4)
        shader.append(NIFBlockFixture.uint32(6))
        let float = try #require(decode(
            "BSEffectShaderPropertyFloatController", shader
        ) as? NIFShaderPropertyController)
        #expect(float.kind == .effectFloat)
        #expect(float.base.interpolatorRef == 4)
        #expect(float.variable == 6)

        var boneLOD = NIFBlockFixture.timeController()
        boneLOD.append(NIFBlockFixture.uint32(0))
        boneLOD.append(NIFBlockFixture.uint32(2))
        boneLOD.append(NIFBlockFixture.uint32(2))
        for refs: [Int32] in [[1, 2], [3]] {
            boneLOD.append(NIFBlockFixture.uint32(UInt32(refs.count)))
            refs.forEach { boneLOD.appendRef($0) }
        }
        let levels = try #require(decode("NiBSBoneLODController", boneLOD) as? NIFBoneLODController)
        #expect(levels.nodeGroups == [[1, 2], [3]])
    }

    @Test func decodesManagerAndPalette() throws {
        var manager = NIFBlockFixture.timeController()
        manager.append(1)
        manager.append(NIFBlockFixture.uint32(1))
        manager.appendRef(2)
        manager.appendRef(3)
        let decoded = try #require(decode("NiControllerManager", manager) as? NIFControllerManager)
        #expect(decoded.cumulative)
        #expect(decoded.sequenceRefs == [2])
        #expect(decoded.objectPaletteRef == 3)

        var palette = Data()
        palette.appendRef(0)
        palette.append(NIFBlockFixture.uint32(1))
        palette.append(NIFFixture.sizedString("Door01"))
        palette.appendRef(4)
        let objects = try #require(decode("NiDefaultAVObjectPalette", palette) as? NIFObjectPalette)
        #expect(objects.block(named: "door01") == 4)
    }

    @Test func decodesBlendInterpolators() throws {
        var managed = Data([1, 0])
        managed.append(NIFBlockFixture.floats([0, -Float.greatestFiniteMagnitude]))
        let float = try #require(decode(
            "NiBlendFloatInterpolator",
            managed
        ) as? NIFBlendInterpolator)
        #expect(float.items.isEmpty)
        #expect(float.value == .float(nil))

        var items = Data([0, 1])
        items.append(NIFBlockFixture.floats([0]))
        items.append(Data(count: 20))
        items.appendRef(5)
        items.append(NIFBlockFixture.floats([1, 1]))
        items.append(2)
        items.append(NIFBlockFixture.floats([0]))
        items.append(1)
        let bool = try #require(decode("NiBlendBoolInterpolator", items) as? NIFBlendInterpolator)
        #expect(bool.items.map(\.interpolatorRef) == [5])
        #expect(bool.value == .bool(true))
    }

    @Test func decodesSkyShaderAndBoxes() throws {
        let sky = try #require(decode(
            "BSSkyShaderProperty", NIFBlockFixture.skyShader(
                texture: "sky\\stars.dds",
                skyObject: 5
            )
        ) as? NIFSkyShaderProperty)
        #expect(sky.skyObject == .stars)
        #expect(sky.material.diffuseTexture == "textures/sky/stars.dds")
        #expect(sky.material.doubleSided)

        let box = try #require(decode("BSMultiBoundOBB", NIFBlockFixture.floats([
            0, 0, 0, 1, 2, 3, 0, 1, 0, -1, 0, 0, 0, 0, 1
        ])) as? NIFMultiBoundBox)
        let corners = box.corners(transform: matrix_identity_float4x4)
        #expect(corners.contains { simd_distance($0, SIMD3(2, -1, 3)) < 1e-5 })
    }
}
