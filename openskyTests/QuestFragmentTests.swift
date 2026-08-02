// The QUST tail of a VMAD field: the quest-stage fragment table and the
// per-alias script sections. Synthetic bytes only (QuestFixture).
//
// Layout: UESP "Skyrim Mod:Mod File Format/VMAD Field", section "QUST
// Records"; xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbVMADFragmentedQUST`
// line 2929. See docs/formats/vmad.md.

import Foundation
@testable import opensky
import Testing

@Suite("QUST VMAD fragments")
struct QuestFragmentTests {
    @Test("decodes the fragment table and the alias script sections")
    func decodesFragmentTail() throws {
        let tail = QuestFixture.fragmentTail(
            fileName: "QF_MQ101_0003C000",
            fragments: [
                .init(stage: 10, script: "QF_MQ101_0003C000", function: "Fragment_0"),
                .init(stage: 20, logEntry: 1, script: "QF_MQ101_0003C000", function: "Fragment_3")
            ],
            aliases: [
                .init(
                    object: VMADFixture.object(0x0003_C000, alias: 3),
                    scripts: [.init("AliasScript", properties: [
                        .init("Count", .integer(4))
                    ])]
                )
            ]
        )
        let data = try decode(tail)

        let section = try #require(data.questFragments)
        #expect(section.extraBindDataVersion == 2)
        #expect(section.fileName == "QF_MQ101_0003C000")
        #expect(section.declaredFragmentCount == 2)
        #expect(!section.fragmentCountMismatch)
        #expect(section.fragments.map(\.stageIndex) == [10, 20])
        #expect(section.fragments.map(\.logEntryIndex) == [0, 1])
        #expect(section.fragments.map(\.functionName) == ["Fragment_0", "Fragment_3"])
        #expect(section.fragments(forStage: 20).map(\.functionName) == ["Fragment_3"])

        #expect(section.aliasScripts.count == 1)
        let alias = try #require(section.aliasScripts.first)
        #expect(alias.aliasID == 3)
        #expect(alias.object.formID == FormID(0x0003_C000))
        #expect(alias.version == 5)
        #expect(alias.objectFormat == .formIDLast)
        #expect(alias.scripts.map(\.name) == ["AliasScript"])
        #expect(alias.scripts.first?.properties.first?.value == .integer(4))
        // The alias object is the point of the section, so it is not counted
        // as a deferred alias-object property the way script properties are.
        #expect(data.skipped.total == 0)
    }

    @Test("reads the alias object with the primary object format")
    func readsAliasObjectInBothFormats() throws {
        for format in [ScriptObjectFormat.formIDFirst, .formIDLast] {
            let tail = QuestFixture.fragmentTail(
                fileName: "QF_Test_00000001",
                fragments: [],
                aliases: [
                    .init(object: VMADFixture.object(0x0102_0304, alias: 7), scripts: [])
                ],
                objectFormat: format
            )
            let data = try decode(tail, objectFormat: format)
            let alias = try #require(data.questFragments?.aliasScripts.first)
            #expect(alias.object.formID == FormID(0x0102_0304))
            #expect(alias.aliasID == 7)
            #expect(alias.objectFormat == format)
        }
    }

    @Test("a tail with no fragments and no aliases still decodes")
    func decodesEmptySection() throws {
        let tail = QuestFixture.fragmentTail(fileName: "QF_Empty_00000001", fragments: [])
        let section = try #require(try decode(tail).questFragments)
        #expect(section.isEmpty)
        #expect(section.fileName == "QF_Empty_00000001")
    }

    @Test("an authored count that disagrees with the table is reported")
    func reportsFragmentCountMismatch() throws {
        // The count is what the reader loops on, so a count of 1 over a
        // two-entry table decodes one fragment and leaves the rest trailing.
        let tail = QuestFixture.fragmentTail(
            declaredCount: 1,
            fileName: "QF_Test_00000001",
            fragments: [
                .init(stage: 1, script: "S", function: "Fragment_0"),
                .init(stage: 2, script: "S", function: "Fragment_1")
            ]
        )
        let data = try decode(tail)
        #expect(data.questFragments == nil)
        #expect(data.skipped.ranked.map(\.name) == ["QUST fragments"])
    }

    @Test("a malformed tail keeps the scripts and records the skip")
    func malformedTailKeepsPrimaryScripts() throws {
        // Truncated after the fragment count: the file-name string cannot be
        // read, so the tail is lost and the primary scripts survive.
        let data = try decode(
            Data([2, 0, 0, 0]),
            scripts: [.init("PrimaryScript", properties: [])]
        )
        #expect(data.questFragments == nil)
        #expect(data.scripts.map(\.name) == ["PrimaryScript"])
        #expect(data.skipped.ranked.map(\.name) == ["QUST fragments"])
        #expect(data.skipped.total == 1)
    }

    @Test("only QUST graduates from the recorded skip")
    func otherCarriersStillSkipTheirTail() throws {
        for carrier: FourCC in ["INFO", "PACK", "PERK", "SCEN"] {
            var data = ScriptData(ownerType: carrier)
            let payload = VMADFixture.payload(
                scripts: [],
                tail: QuestFixture.fragmentTail(fileName: "F", fragments: [])
            )
            #expect(try data.decode(field: ESMField(type: "VMAD", data: payload)))
            #expect(data.questFragments == nil)
            #expect(data.skipped.ranked.map(\.name) == ["\(carrier) fragments"])
        }
    }

    @Test("the quest record surfaces its fragments")
    func questRecordSurfacesFragments() throws {
        var fields = QuestFixture.editorID("MQ101")
        fields += QuestFixture.vmad(
            tail: QuestFixture.fragmentTail(
                fileName: "QF_MQ101_0003C000",
                fragments: [.init(stage: 10, script: "QF", function: "Fragment_0")],
                aliases: [.init(object: VMADFixture.object(0x0003_C000, alias: 0), scripts: [])]
            )
        )
        fields += QuestFixture.stage(10)
        let quest = try QuestFixture.quest(formID: 0x0003_C000, fields: fields)

        #expect(quest.fragments.map(\.stageIndex) == [10])
        #expect(quest.aliasScripts.count == 1)
        #expect(quest.script.skipped.total == 0)
        #expect(quest.skipped.isEmpty)
    }

    private func decode(
        _ tail: Data,
        scripts: [VMADFixture.Script] = [],
        objectFormat: ScriptObjectFormat = .formIDLast
    ) throws -> ScriptData {
        var data = ScriptData(ownerType: "QUST")
        let payload = VMADFixture.payload(
            objectFormat: objectFormat,
            scripts: scripts,
            tail: tail
        )
        _ = try data.decode(field: ESMField(type: "VMAD", data: payload))
        return data
    }
}
