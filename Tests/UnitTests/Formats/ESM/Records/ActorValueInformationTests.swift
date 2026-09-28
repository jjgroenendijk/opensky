// Synthetic AVIF decode coverage. Fixtures are authored from the cited field
// layout and contain no bytes from the game install.

import Foundation
@testable import opensky
import Testing

struct ActorValueInformationTests {
    @Test
    func decodesIdentitySkillUseParametersAndPerkTree() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("AVOneHanded"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("One-Handed"))
        fields += ESMFixture.field("DESC", ESMFixture.zstring("Swords and axes."))
        fields += ESMFixture.field("ANAM", ESMFixture.zstring("1H"))
        fields += ESMFixture.field("ICON", ESMFixture.zstring("Interface\\skill.dds"))
        fields += ESMFixture.field("CNAM", ActorValueInformationFixture.words([1]))
        fields += ESMFixture.field("AVSK", ActorValueInformationFixture.skillUse())
        fields += ActorValueInformationFixture.node(
            perk: 0,
            parentRequired: 0xFFFF_0000,
            column: 0,
            row: 0,
            horizontal: 0,
            vertical: 0,
            skill: 0x0A,
            connections: [1, 2],
            index: 0
        )
        fields += ActorValueInformationFixture.node(
            perk: 0x50,
            parentRequired: 1,
            column: 3,
            row: 4,
            horizontal: 0.25,
            vertical: 0.5,
            skill: 0x0A,
            connections: [],
            index: 1
        )
        fields += ESMFixture.field("ZZZZ", Data([1]))

        let value = try ActorValueInformation(
            record: ActorValueInformationFixture.record(type: "AVIF", formID: 0x0A, fields: fields),
            localized: false
        )

        #expect(value.formID == FormID(0x0A))
        #expect(value.editorID == "AVOneHanded")
        #expect(value.name == .inline("One-Handed"))
        #expect(value.description == .inline("Swords and axes."))
        #expect(value.abbreviation == "1H")
        #expect(value.iconPath == "Interface\\skill.dds")
        #expect(value.skillCategory == .combat)
        #expect(value.hasPerkTree)
        #expect(value.vanillaActorValueIndex == ActorValueIdentity.firstSkillIndex)
        #expect(value.skipped.counts[.unknownField("ZZZZ")] == 1)

        let use = try #require(value.skillUse)
        #expect(use.useMultiplier == 1.5)
        #expect(use.useOffset == 2.5)
        #expect(use.improveMultiplier == 3.5)
        #expect(use.improveOffset == 4.5)

        try expectFixturePerkTree(value)
    }

    /// The two-node tree the identity fixture carries: an entry node with a
    /// NULL perk and two connection lines, then the box those lines reach.
    private func expectFixturePerkTree(_ value: ActorValueInformation) throws {
        #expect(value.perkTree.count == 2)
        let root = try #require(value.perkTree.first)
        #expect(root.isRoot)
        #expect(root.perk == nil)
        #expect(root.parentRequiredRaw == 0xFFFF_0000)
        #expect(root.connections == [1, 2])
        #expect(root.associatedSkill == FormID(0x0A))
        let leaf = try #require(value.perkTree.last)
        #expect(leaf.perk == FormID(0x50))
        #expect(leaf.index == 1)
        #expect(leaf.parentRequired)
        #expect(leaf.connections.isEmpty)
        #expect(leaf.position == PerkGridPosition(
            column: 3,
            row: 4,
            horizontal: 0.25,
            vertical: 0.5
        ))
    }

    /// The record-level CNAM and a node's connection CNAM share a tag, so the
    /// only thing separating them is whether a PNAM has opened a node yet.
    @Test
    func recordCategoryAndNodeConnectionsShareTheCNAMTag() throws {
        var fields = ESMFixture.field("CNAM", ActorValueInformationFixture.words([3]))
        fields += ActorValueInformationFixture.node(connections: [7, 9], index: 0)
        let value = try ActorValueInformation(
            record: ActorValueInformationFixture.record(type: "AVIF", fields: fields),
            localized: false
        )

        #expect(value.categoryRaw == 3)
        #expect(value.skillCategory == .stealth)
        #expect(value.perkTree.count == 1)
        #expect(value.perkTree.first?.connections == [7, 9])
    }

    @Test
    func nonSkillRecordCarriesNoTreeAndNoUseParameters() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("AVHealth"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Health"))
        let value = try ActorValueInformation(
            record: ActorValueInformationFixture.record(type: "AVIF", fields: fields),
            localized: false
        )

        #expect(!value.hasPerkTree)
        #expect(value.perkTree.isEmpty)
        #expect(value.skillUse == nil)
        #expect(value.skillCategory == nil)
        #expect(value.vanillaActorValueIndex == 24)
    }

    @Test
    func unknownCategoryKeepsItsRawWord() throws {
        let fields = ESMFixture.field("CNAM", ActorValueInformationFixture.words([0x0BAD_F00D]))
        let value = try ActorValueInformation(
            record: ActorValueInformationFixture.record(type: "AVIF", fields: fields),
            localized: false
        )

        #expect(value.categoryRaw == 0x0BAD_F00D)
        #expect(value.skillCategory == .unknown(raw: 0x0BAD_F00D))
    }

    @Test
    func rejectsWrongTypeButSurvivesTruncatedFields() throws {
        #expect(throws: ESMError.self) {
            _ = try ActorValueInformation(
                record: ActorValueInformationFixture.record(type: "MGEF", fields: Data()),
                localized: false
            )
        }

        var fields = ESMFixture.field("EDID", ESMFixture.zstring("AVSneak"))
        fields += ESMFixture.field("AVSK", Data(count: 12))
        fields += ESMFixture.field("PNAM", ActorValueInformationFixture.words([0x60]))
        fields += ESMFixture.field("XNAM", Data(count: 2))
        let value = try ActorValueInformation(
            record: ActorValueInformationFixture.record(type: "AVIF", fields: fields),
            localized: false
        )

        #expect(value.editorID == "AVSneak")
        #expect(value.skillUse == nil)
        #expect(value.skipped.counts[.malformedField("AVSK")] == 1)
        #expect(value.skipped.counts[.malformedField("XNAM")] == 1)
        // The node opened by PNAM is still emitted, and reported as incomplete.
        #expect(value.perkTree.count == 1)
        #expect(value.perkTree.first?.perk == FormID(0x60))
        #expect(value.skipped.counts[.incompletePerkTreeNode] == 1)
    }

    @Test
    func perkTreeRoundTripsThroughTheRecordTextDump() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("AVAlchemy"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Alchemy"))
        fields += ESMFixture.field("CNAM", ActorValueInformationFixture.words([3]))
        fields += ESMFixture.field("AVSK", ActorValueInformationFixture.skillUse())
        fields += ActorValueInformationFixture.node(perk: 0x71, connections: [6], index: 5)
        let record = try ActorValueInformationFixture.record(type: "AVIF", fields: fields)

        let dump = RecordTextDump.dump(record: record, localized: false)

        #expect(dump.contains("decoded AVIF: editorID AVAlchemy"))
        #expect(dump.contains("actor value Alchemy (index 16)"))
        #expect(dump.contains("category stealth"))
        #expect(dump.contains("skill use: use mult 1.5000"))
        #expect(dump.contains("perk tree (1 nodes):"))
        #expect(dump.contains("#5 perk 00000071"))
        #expect(dump.contains("lines to [6]"))
    }
}

enum ActorValueInformationFixture {
    static func skillUse(
        useMultiplier: Float = 1.5,
        useOffset: Float = 2.5,
        improveMultiplier: Float = 3.5,
        improveOffset: Float = 4.5
    ) -> Data {
        words([
            useMultiplier.bitPattern,
            useOffset.bitPattern,
            improveMultiplier.bitPattern,
            improveOffset.bitPattern
        ])
    }

    /// One perk-tree node in the field order the spec gives: PNAM, FNAM, XNAM,
    /// YNAM, HNAM, VNAM, SNAM, the CNAM connection run, then INAM.
    static func node(
        perk: UInt32 = 0,
        parentRequired: UInt32 = 1,
        column: UInt32 = 0,
        row: UInt32 = 0,
        horizontal: Float = 0,
        vertical: Float = 0,
        skill: UInt32 = 0,
        connections: [UInt32] = [],
        index: UInt32 = 0
    ) -> Data {
        var data = ESMFixture.field("PNAM", words([perk]))
        data += ESMFixture.field("FNAM", words([parentRequired]))
        data += ESMFixture.field("XNAM", words([column]))
        data += ESMFixture.field("YNAM", words([row]))
        data += ESMFixture.field("HNAM", words([horizontal.bitPattern]))
        data += ESMFixture.field("VNAM", words([vertical.bitPattern]))
        data += ESMFixture.field("SNAM", words([skill]))
        for connection in connections {
            data += ESMFixture.field("CNAM", words([connection]))
        }
        data += ESMFixture.field("INAM", words([index]))
        return data
    }

    static func record(type: String, formID: UInt32 = 0, fields: Data) throws -> ESMRecord {
        let file = try ESMFile(
            data: ESMFixture.tes4()
                + ESMFixture.topGroup(
                    type,
                    contents: ESMFixture.record(type, formID: formID, data: fields)
                )
        )
        guard let group = file.topGroups.first else {
            throw ESMError.malformed("fixture has no top group")
        }
        guard let child = try group.children().first else {
            throw ESMError.malformed("fixture group has no child")
        }
        guard case let .record(record) = child else {
            throw ESMError.malformed("fixture child is not a record")
        }
        return record
    }

    static func words(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values {
            data.appendUInt32(value)
        }
        return data
    }
}
