import Foundation
@testable import opensky
import simd
import Testing

struct TreeLODTests {
    private func listData(width: Float = 320, uvMaxX: Float = 0.75) -> Data {
        var data = Data()
        data.appendUInt32(1)
        data.appendUInt32(7)
        data.appendFloat32(width)
        data.appendFloat32(640)
        data.appendFloat32(0.25)
        data.appendFloat32(0.5)
        data.appendFloat32(uvMaxX)
        data.appendFloat32(1)
        data.appendUInt32(99)
        return data
    }

    private func blockData(typeIndex: Int32 = 7, scale: Float = 1.5) -> Data {
        var data = Data()
        data.appendUInt32(1)
        data.appendUInt32(UInt32(bitPattern: typeIndex))
        data.appendUInt32(1)
        data.appendFloat32(4096)
        data.appendFloat32(-8192)
        data.appendFloat32(128)
        data.appendFloat32(.pi / 4)
        data.appendFloat32(scale)
        data.appendUInt32(0x1234)
        data.appendUInt32(11)
        data.appendUInt32(12)
        return data
    }

    @Test func decodesListAndBlockLayouts() throws {
        let list = try TreeLODList(data: listData())
        let type = try #require(list.types.first)
        #expect(type.index == 7)
        #expect(type.width == 320)
        #expect(type.height == 640)
        #expect(type.uvMin == SIMD2(0.25, 0.5))
        #expect(type.uvMax == SIMD2(0.75, 1))
        #expect(type.metadata == 99)

        let block = try TreeLODBlock(data: blockData(), list: list)
        let reference = try #require(block.groups.first?.references.first)
        #expect(block.referenceCount == 1)
        #expect(reference.position == SIMD3(4096, -8192, 128))
        #expect(reference.rotation == .pi / 4)
        #expect(reference.scale == 1.5)
        #expect(reference.formID == 0x1234)
        #expect(reference.metadata1 == 11)
        #expect(reference.metadata2 == 12)
    }

    @Test func rejectsMalformedCountsUVsReferencesAndUnknownTypes() throws {
        var negativeCount = Data()
        negativeCount.appendUInt32(UInt32.max)
        #expect(throws: TreeLODError.invalidCount(-1)) {
            try TreeLODList(data: negativeCount)
        }
        #expect(throws: TreeLODError.invalidType(index: 7)) {
            try TreeLODList(data: listData(width: 0))
        }
        #expect(try TreeLODList(data: listData(uvMaxX: 1.001)).types.count == 1)

        let list = try TreeLODList(data: listData())
        #expect(throws: TreeLODError.unknownTypeIndex(8)) {
            try TreeLODBlock(data: blockData(typeIndex: 8), list: list)
        }
        #expect(throws: TreeLODError.invalidReference(typeIndex: 7, referenceIndex: 0)) {
            try TreeLODBlock(data: blockData(scale: 0), list: list)
        }
    }

    @Test func billboardBuildsTwoCrossedDoubleSidedAtlasPlanes() throws {
        let type = try #require(TreeLODList(data: listData()).types.first)
        let model = TreeLODBillboard.model(
            type: type,
            atlasPath: "textures\\terrain\\tamriel\\trees\\tamrieltreelod.dds"
        )
        let mesh = try #require(model.meshes.first)
        let material = try #require(model.materials.first)

        #expect(mesh.positions.count == 8)
        #expect(mesh.indices.count == 12)
        #expect(mesh.positions[0] == SIMD3(-160, 0, 0))
        #expect(mesh.positions[6] == SIMD3(0, 160, 640))
        #expect(mesh.uvs[0] == SIMD2(0.25, 1))
        #expect(mesh.uvs[2] == SIMD2(0.75, 0.5))
        #expect(material.doubleSided)
        #expect(material.alphaTestThreshold == 0.5)
    }
}
