// Havok binary tagfile decode over synthetic streams from HKTagfileFixture.
// Layout: docs/formats/hkt-tagfile.md.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsAnimation
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct HKTagfileTests {
    /// Type words: 2 int, 3 real, 4 vector4, 8 object, 9 struct, 10 string;
    /// 0x10 marks an array.
    private func rootAndBone(version: Int) -> HKTagfileFixture {
        var fixture = HKTagfileFixture()
        fixture.fileInfo(version: version)
        fixture.classDefinition("hkaBone", members: [.init("name", 10), .init("lock", 1)])
        fixture.classDefinition(
            "hkaSkeleton",
            version: 3,
            members: [
                .init("name", 10), .init("parentIndices", 0x12),
                .init("bones", 0x19, "hkaBone"), .init("pose", 0x14),
                .init("next", 8, "hkaSkeleton")
            ]
        )
        return fixture
    }

    @Test func decodesClassesAndAVersionThreeObject() throws {
        var fixture = rootAndBone(version: 3)
        fixture.object(classIndex: 2)
        fixture.bytes([0x1F]) // name, parentIndices, bones, pose, next
        fixture.string("Root")
        fixture.int(2) // two parent indices
        fixture.int(4) // the int-array header every vanilla file writes
        fixture.int(-1)
        fixture.int(0)
        fixture.int(2) // two bones
        fixture.bytes([0x01]) // only the name column
        fixture.string("b_ROOT")
        fixture.string("Root") // a back reference to an earlier string
        fixture.int(1)
        [Float](arrayLiteral: 0, 0, 1, 0).forEach { fixture.float($0) }
        fixture.int(0) // null object
        fixture.end()

        let file = try HKTagfile(data: fixture.data)
        #expect(file.version == 3)
        #expect(file.hasEndTag)
        #expect(file.classes.map(\.name) == ["", "hkaBone", "hkaSkeleton"])
        #expect(file.classes[2].version == 3)
        let skeleton = try #require(file.objects.first)
        #expect(file.className(of: skeleton) == "hkaSkeleton")
        #expect(skeleton["name"] == .string("Root"))
        #expect(skeleton["parentIndices"] == .array([.int(-1), .int(0)]))
        #expect(skeleton["pose"] == .array([.vector([0, 0, 1, 0])]))
        #expect(skeleton["next"] == .reference(.null))
        #expect(HKTCensus(file: file).skeletonBones == ["b_ROOT", "Root"])
        #expect(file.unexpectedIntArrayHeaders == 0)
    }

    @Test func versionZeroWritesObjectsInPlaceAndMayOmitTheEnd() throws {
        var fixture = rootAndBone(version: 0)
        fixture.object(classIndex: 2)
        fixture.bytes([0x12]) // parentIndices and next
        fixture.int(1)
        fixture.int(-1) // no int-array header in version 0
        fixture.object(classIndex: 2, remembered: false)
        fixture.bytes([0x01])
        fixture.string("Inner")

        let file = try HKTagfile(data: fixture.data)
        #expect(!file.hasEndTag)
        #expect(file.objects.count == 2)
        let outer = try #require(file.objects.last)
        guard case let .reference(reference)? = outer["next"] else {
            Issue.record("next is not a reference")
            return
        }
        #expect(file.object(reference)?["name"] == .string("Inner"))
    }

    @Test func remembersObjectsForLaterReferences() throws {
        var fixture = rootAndBone(version: 3)
        fixture.object(classIndex: 2)
        fixture.bytes([0x10])
        fixture.int(2) // points at the second remembered object
        fixture.object(classIndex: 2)
        fixture.bytes([0x01])
        fixture.string("Target")
        fixture.end()

        let file = try HKTagfile(data: fixture.data)
        #expect(file.remembered == [nil, 0, 1])
        #expect(file.object(.remembered(2))?["name"] == .string("Target"))
        #expect(file.allMembers(ofClass: 2).count == 5)
    }

    @Test func countsAClothClass() throws {
        var fixture = HKTagfileFixture()
        fixture.fileInfo(version: 3)
        fixture.classDefinition("hclClothData", members: [])
        fixture.end()
        let census = try HKTCensus(file: HKTagfile(data: fixture.data))
        #expect(census.clothClasses == ["hclClothData"])
        #expect(census.definitions == [HKTCensus.ClassVersion(name: "hclClothData", version: 0)])
    }

    @Test func rejectsMalformedStreams() {
        #expect(throws: HKTError.badMagic(found0: 1, found1: 2)) {
            try HKTagfile(data: HKTagfileFixture(magic0: 1, magic1: 2).data)
        }
        var unknownTag = HKTagfileFixture()
        unknownTag.int(9)
        #expect(throws: HKTError.unknownTag(9, offset: 8)) {
            try HKTagfile(data: unknownTag.data)
        }
        var badString = HKTagfileFixture()
        badString.int(2)
        badString.int(-40)
        #expect(throws: HKTError.badStringReference(-40, offset: 9)) {
            try HKTagfile(data: badString.data)
        }
        var badType = HKTagfileFixture()
        badType.classDefinition("A", members: [.init("m", 0x4F)])
        #expect(throws: (any Error).self) { try HKTagfile(data: badType.data) }
        var hugeCount = rootAndBone(version: 3)
        hugeCount.object(classIndex: 2)
        hugeCount.bytes([0x02])
        hugeCount.int(1_000_000)
        #expect(throws: (any Error).self) { try HKTagfile(data: hugeCount.data) }
        var truncated = HKTagfileFixture()
        truncated.bytes([0x80])
        #expect(throws: HKTError.truncated(offset: 9)) { try HKTagfile(data: truncated.data) }
    }
}
