// The node subclass, legacy shape, and sky shader fields, read by name over
// synthetic blocks (docs/formats/nif.md#node-subclasses).

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct NIFNodeFieldTests {
    private func file(_ type: String, _ data: Data, strings: [String] = []) throws -> NIFFile {
        try NIFFile(data: NIFFixture.file(blocks: [.init(type, data)], strings: strings))
    }

    private func decoded(_ type: String, _ data: Data, strings: [String] = []) throws -> Any? {
        let file = try file(type, data, strings: strings)
        return try NIFBlockDecoders.decode(file.blocks[0], header: file.header)
    }

    @Test func nodeSubclassesKeepTheirNodeAndFields() throws {
        var valueData = NIFFixture.niNode(children: [4])
        valueData.append(NIFBlockFixture.uint32(9))
        valueData.append(2)
        let value = try #require(decoded("BSValueNode", valueData) as? NIFValueNode)
        #expect(value.node.children == [4])
        #expect(value.flags == 2)
        var leaf = NIFFixture.niNode()
        leaf.append(NIFBlockFixture.uint32(9))
        leaf.append(2)
        let model = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1])),
            .init("BSValueNode", leaf)
        ]))
        #expect(try model.addOnNodes().first?.flags == 2)

        var rangeData = NIFFixture.niNode(children: [5])
        rangeData.append(contentsOf: [1, 3, 2])
        let range = try #require(decoded("BSBlastNode", rangeData) as? NIFRangeNode)
        #expect(range.node.children == [5])
        #expect(range.current == 2)

        var masterData = NIFFixture.niNode(children: [6])
        masterData.appendUInt16(1)
        masterData.append(NIFBlockFixture.uint32(0))
        let master = try #require(decoded(
            "BSMasterParticleSystem", masterData
        ) as? NIFMasterParticleSystem)
        #expect(master.node.children == [6])
    }

    @Test func legacyShapeKeepsMaterialsAndLevels() throws {
        let shape = try file("BSLODTriShape", NIFBlockFixture.legacyTriShape(
            dataRef: 1, materialNames: [0], lodSizes: [12, 6, 2]
        ), strings: ["Stone"])
        var reader = BinaryReader(shape.blocks[0].data)
        let decoded = try NIFLegacyTriShape(reader: &reader, header: shape.header, isLOD: true)
        #expect(decoded.materialNames == ["Stone"])
        #expect(decoded.lodSizes == [12, 6, 2])
    }

    @Test func skyShaderKeepsItsNameAndFlags() throws {
        let sky = try #require(decoded("BSSkyShaderProperty", NIFBlockFixture.skyShader(
            nameIndex: 0, shaderFlags: (0x8000_0000, 0x10), texture: "sky\\moon.dds", skyObject: 7
        ), strings: ["Moon"]) as? NIFSkyShaderProperty)
        #expect(sky.name == "Moon")
        #expect(sky.shaderFlags1 == 0x8000_0000)
        #expect(sky.shaderFlags2 == 0x10)
        #expect(sky.skyObject == .moonStarsMask)
    }
}
