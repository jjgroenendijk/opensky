// Packfile decoders over tagfile objects: members found by name, pointers
// through remembered indices. Synthetic streams from HKTagfileFixture.

import Foundation
@testable import OpenSkyFormatsAnimation
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct HKXObjectGraphTagfileTests {
    /// Type words: 1 byte, 2 int, 6 vector12, 8 object, 9 struct, 10 string;
    /// 0x10 marks an array.
    @Test func decodesASkeletonFromATagfile() throws {
        var fixture = HKTagfileFixture()
        fixture.fileInfo(version: 3)
        fixture.classDefinition(
            "hkaBone", members: [.init("name", 10), .init("lockTranslation", 1)]
        )
        fixture.classDefinition("hkaSkeleton", version: 3, members: [
            .init("name", 10), .init("parentIndices", 0x12),
            .init("bones", 0x19, "hkaBone"), .init("referencePose", 0x16)
        ])
        fixture.object(classIndex: 2)
        fixture.bytes([0x0F])
        fixture.string("Rig")
        fixture.int(2)
        fixture.int(4)
        fixture.int(-1)
        fixture.int(0)
        fixture.int(2)
        fixture.bytes([0x03])
        fixture.string("Root")
        fixture.string("Blade01")
        fixture.bytes([0, 1])
        fixture.int(2)
        let rest: [Float] = [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1]
        let blade: [Float] = [0, 0, 100, 0, 0, 0, 0, 1, 1, 1, 1, 1]
        (rest + blade).forEach { fixture.float($0) }
        fixture.end()

        #expect(HKXObjectGraph.isTagfile(fixture.data))
        let graph = try HKXObjectGraph.decode(fixture.data)
        let skeleton = try #require(HKASkeleton.skeletons(in: graph).first)
        #expect(skeleton.name == "Rig")
        #expect(skeleton.boneNames == ["Root", "Blade01"])
        #expect(skeleton.parentIndices == [-1, 0])
        #expect(skeleton.lockTranslation == [false, true])
        #expect(skeleton.referencePose[1].translation == SIMD3(0, 0, 100))
    }

    @Test func followsAPointerToTheProjectStrings() throws {
        var fixture = HKTagfileFixture()
        fixture.fileInfo(version: 3)
        fixture.classDefinition("hkbProjectStringData", members: [
            .init("animationFilenames", 0x1A), .init("behaviorFilenames", 0x1A),
            .init("characterFilenames", 0x1A)
        ])
        fixture.classDefinition("hkbProjectData", members: [
            .init("worldUpVector", 4), .init("stringData", 8, "hkbProjectStringData")
        ])
        fixture.object(classIndex: 2)
        fixture.bytes([0x02])
        fixture.int(2) // remembered index of the string data written next
        fixture.object(classIndex: 1)
        fixture.bytes([0x04])
        fixture.int(1)
        fixture.string("Characters\\Character.hkx")
        fixture.end()

        let graph = try HKXObjectGraph.decode(fixture.data)
        let project = try #require(graph.objects(ofClass: HKBProjectData.className).first)
        let target = HKXPointerTarget(
            sectionIndex: project.sectionIndex, dataOffset: project.dataOffset
        )
        #expect(graph.className(at: target) == HKBProjectData.className)
        let data = try #require(HKBProjectData.decode(at: target, in: graph))
        #expect(data.characterFilenames == ["Characters\\Character.hkx"])
        #expect(data.animationFilenames.isEmpty)
    }

    @Test func pathsDropTheMemberPrefixAndTheClassScope() {
        let steps = HKXObjectCursor.tagPath("hkaBone::m_name")
        #expect(steps == [HKXObjectCursor.TagStep(name: "name", index: nil)])
        #expect(HKXObjectCursor.tagPath("m_controlData.m_gains[2]") == [
            HKXObjectCursor.TagStep(name: "controlData", index: nil),
            HKXObjectCursor.TagStep(name: "gains", index: 2)
        ])
    }
}
