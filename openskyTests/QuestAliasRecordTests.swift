// The ALST/ALLS alias run of a QUST record, split out of QuestRecordTests so
// each suite stays inside the strict-lint type-body cap. Synthetic bytes only
// (QuestFixture).
//
// Layout: UESP "Skyrim Mod:Mod File Format/QUST", "Aliases"; xEdit dev-4.1.6
// Core/wbDefinitionsTES5.pas reference aliases line 8869, location aliases
// 8971. See docs/formats/records.md.

import Foundation
@testable import opensky
import Testing

@Suite("QUST aliases")
struct QuestAliasRecordTests {
    /// One row of the fill-type matrix: the subrecords an alias carries and
    /// the fill type they should add up to.
    private struct FillCase {
        let fill: Data
        let expected: Quest.Alias.FillType
        let location: Bool

        init(_ fill: Data, _ expected: Quest.Alias.FillType, location: Bool = false) {
            self.fill = fill
            self.expected = expected
            self.location = location
        }
    }

    @Test("aliases open on ALST or ALLS and close on ALED")
    func groupsAliasesBetweenTheirMarkers() throws {
        var fields = QuestFixture.word("ANAM", 3)
        fields += QuestFixture.alias(
            id: 0,
            name: "Target",
            fill: QuestFixture.word("ALFR", 0x0AA),
            extras: QuestFixture.condition(functionIndex: 42)
                + QuestFixture.word("ALSP", 0x0B1)
                + QuestFixture.word("ALSP", 0x0B2)
        )
        fields += QuestFixture.alias(
            id: 1,
            name: "Place",
            location: true,
            fill: QuestFixture.word("ALFL", 0x0CC)
        )
        let quest = try QuestFixture.quest(fields: fields)

        #expect(quest.aliases.count == 2)
        #expect(quest.aliases[0].category == .reference)
        #expect(quest.aliases[0].forcedReference == FormID(0x0AA))
        #expect(quest.aliases[0].fillType == .specificReference)
        // The CTDA landed inside the alias, not on the quest.
        #expect(quest.aliases[0].matchConditions.conditions.count == 1)
        #expect(quest.dialogueConditions.isEmpty)
        #expect(quest.aliases[0].spells == [FormID(0x0B1), FormID(0x0B2)])
        #expect(quest.aliases[1].category == .location)
        #expect(quest.aliases[1].forcedLocation == FormID(0x0CC))
        #expect(quest.aliases[1].fillType == .specificLocation)
        #expect(quest.skipped.isEmpty)
    }

    @Test("an alias FNAM is alias flags, not objective flags")
    func aliasFieldsShadowQuestLevelSpellings() throws {
        var fields = QuestFixture.objective(10, flags: 1, text: "objective")
        fields += QuestFixture.word("ANAM", 1)
        fields += QuestFixture.alias(
            id: 0,
            name: "Item",
            flags: 0x04,
            extras: QuestFixture.word("KSIZ", 1)
                + QuestFixture.word("KWDA", 0x0D1)
                + QuestFixture.word("COCT", 1)
                + cnto(item: 0x0E1, count: 2)
        )
        let quest = try QuestFixture.quest(fields: fields)

        #expect(quest.objectives[0].flags == [.oredWithPrevious])
        #expect(quest.aliases[0].flags == [.questObject])
        #expect(quest.aliases[0].keywords.keywords == [FormID(0x0D1)])
        #expect(quest.aliases[0].declaredItemCount == 1)
        #expect(quest.aliases[0].items == [
            Quest.Alias.Item(item: FormID(0x0E1), count: 2)
        ])
        #expect(quest.skipped.isEmpty)
    }

    @Test("an alias cut off without ALED is kept and counted")
    func unterminatedAliasIsKeptAndCounted() throws {
        var fields = QuestFixture.alias(
            id: 0,
            name: "First",
            fill: QuestFixture.word("ALFR", 0x0AA),
            terminated: false
        )
        fields += QuestFixture.alias(id: 1, name: "Second")
        let quest = try QuestFixture.quest(fields: fields)

        #expect(quest.aliases.map(\.id) == [0, 1])
        #expect(quest.aliases[0].name == "First")
        #expect(quest.skipped.ranked.map(\.name) == ["unterminated alias"])
    }

    @Test("an ALED with no alias open costs itself")
    func strayAliasTerminatorCostsItself() throws {
        let quest = try QuestFixture.quest(fields: QuestFixture.marker("ALED"))
        #expect(quest.aliases.isEmpty)
        #expect(quest.skipped.ranked.map(\.name) == ["orphan ALED"])
    }

    @Test("a truncated ALST loses the group, not the record")
    func truncatedAliasOpenerCostsTheGroup() throws {
        var fields = ESMFixture.field("ALST", Data([0, 0]))
        fields += ESMFixture.field("ALID", ESMFixture.zstring("Lost"))
        fields += QuestFixture.marker("ALED")
        fields += QuestFixture.alias(id: 7, name: "Kept")
        let quest = try QuestFixture.quest(fields: fields)

        #expect(quest.aliases.map(\.id) == [7])
        #expect(quest.skipped.ranked.map(\.name).sorted() == [
            "malformed ALST", "orphan ALED", "unknown ALID"
        ])
    }

    @Test("every documented fill type is reported from its own subrecords")
    func reportsEveryFillType() throws {
        let cases: [FillCase] = [
            .init(QuestFixture.word("ALFR", 1), .specificReference),
            .init(QuestFixture.word("ALUA", 2), .uniqueActor),
            .init(QuestFixture.word("ALFL", 3), .specificLocation, location: true),
            .init(
                QuestFixture.signedWord("ALFA", 1) + QuestFixture.word("ALRT", 4),
                .locationAliasReference
            ),
            .init(
                QuestFixture.signedWord("ALFA", 1) + QuestFixture.word("KNAM", 5),
                .referenceAliasLocation, location: true
            ),
            .init(
                QuestFixture.word("ALEQ", 6) + QuestFixture.signedWord("ALEA", 2),
                .externalAlias
            ),
            .init(
                QuestFixture.word("ALCO", 7) + QuestFixture.word("ALCA", 0x8000)
                    + QuestFixture.word("ALCL", 1),
                .createReferenceToObject
            ),
            .init(
                QuestFixture.signedWord("ALNA", 3) + QuestFixture.word("ALNT", 0),
                .nearAlias
            ),
            .init(
                QuestFixture.word("ALFE", 9) + QuestFixture.word("ALFD", 1),
                .fromEvent, location: true
            ),
            .init(Data(), .none)
        ]
        for fillCase in cases {
            let quest = try QuestFixture.quest(fields: QuestFixture.alias(
                id: 0,
                name: "A",
                location: fillCase.location,
                fill: fillCase.fill
            ))
            let alias = try #require(quest.aliases.first)
            #expect(alias.fillType == fillCase.expected, "\(fillCase.expected.name) not reported")
            #expect(quest.skipped.isEmpty)
        }
    }

    // MARK: - Helpers

    private func cnto(item: UInt32, count: Int32) -> Data {
        var data = Data()
        data.appendUInt32(item)
        data.appendUInt32(UInt32(bitPattern: count))
        return ESMFixture.field("CNTO", data)
    }
}
