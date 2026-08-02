// QUST decode over synthetic field bytes only (QuestFixture) — never
// extracted game files (AGENTS.md "Legal & IP boundary").
//
// Layouts: UESP "Skyrim Mod:Mod File Format/QUST" and xEdit dev-4.1.6
// Core/wbDefinitionsTES5.pas `wbRecord(QUST, 'Quest', ...)` line 8759.
// See docs/formats/records.md.

import Foundation
@testable import opensky
import Testing

@Suite("QUST record")
struct QuestRecordTests {
    // MARK: - Whole-record decode

    @Test("decodes the header, both condition runs and every grouped sequence")
    func decodesCompleteQuest() throws {
        var fields = QuestFixture.editorID("MQ101")
        fields += QuestFixture.full("Unbound")
        fields += QuestFixture.general(flags: 0x0101, priority: 80, type: 1)
        fields += QuestFixture.word("ENAM", fourCC("CRIM"))
        fields += QuestFixture.word("QTGL", 0x0DE1)
        fields += ESMFixture.field("FLTR", ESMFixture.zstring("Main Quest\\"))
        fields += QuestFixture.condition(functionIndex: 100)
        fields += QuestFixture.marker("NEXT")
        fields += QuestFixture.condition(functionIndex: 200)
        fields += QuestFixture.stage(10, flags: 0x02)
        fields += QuestFixture.logEntry(text: "Escape Helgen.")
        fields += QuestFixture.stage(20)
        fields += QuestFixture.logEntry(flags: 0x01, text: "You escaped.")
        fields += QuestFixture.objective(10, text: "Escape")
        fields += QuestFixture.target(alias: 3, ignoresLocks: true)
        fields += QuestFixture.word("ANAM", 4)
        fields += QuestFixture.alias(
            id: 3,
            name: "QuestGiver",
            flags: 0x40,
            fill: QuestFixture.word("ALUA", 0x0BEEF)
        )
        let quest = try QuestFixture.quest(formID: 0x0003_C000, fields: fields)

        #expect(quest.formID == FormID(0x0003_C000))
        #expect(quest.editorID == "MQ101")
        #expect(quest.name == .inline("Unbound"))
        #expect(quest.flags.contains(.startGameEnabled))
        #expect(quest.flags.contains(.runOnce))
        #expect(quest.priority == 80)
        #expect(quest.kind == .mainQuest)
        #expect(quest.event == "CRIM")
        #expect(quest.textDisplayGlobals == [FormID(0x0DE1)])
        #expect(quest.objectWindowFilter == "Main Quest\\")
        #expect(quest.nextAliasID == 4)
        #expect(quest.skipped.isEmpty)

        // NEXT splits the two runs; each condition lands on exactly one side.
        #expect(quest.dialogueConditions.conditions.map(\.functionIndex) == [100])
        #expect(quest.storyManagerConditions.conditions.map(\.functionIndex) == [200])

        #expect(quest.stages.map(\.index) == [10, 20])
        #expect(quest.stages[0].flags == [.startUpStage])
        #expect(quest.stages[0].logEntries.first?.text == .inline("Escape Helgen."))
        #expect(quest.stages[1].logEntries.first?.flags == [.completeQuest])

        #expect(quest.objectives.count == 1)
        #expect(quest.objectives[0].index == 10)
        #expect(quest.objectives[0].displayText == .inline("Escape"))
        #expect(quest.objectives[0].targets.count == 1)
        #expect(quest.objectives[0].targets[0].aliasID == 3)
        #expect(quest.objectives[0].targets[0].compassMarkerIgnoresLocks)

        #expect(quest.aliases.count == 1)
        #expect(quest.aliases[0].id == 3)
        #expect(quest.aliases[0].name == "QuestGiver")
        #expect(quest.aliases[0].category == .reference)
        #expect(quest.aliases[0].flags == [.essential])
        #expect(quest.aliases[0].uniqueActor == FormID(0x0BEEF))
        #expect(quest.aliases[0].fillType == .uniqueActor)
        #expect(quest.alias(id: 3)?.name == "QuestGiver")
        #expect(quest.alias(id: 99) == nil)
    }

    @Test("rejects a record of another type")
    func rejectsWrongRecordType() throws {
        let record = try QuestFixture.parse(
            ESMFixture.record("CONT", data: QuestFixture.editorID("NotAQuest"))
        )
        #expect(throws: ESMError.self) {
            _ = try Quest(record: record)
        }
    }

    @Test("an empty record decodes to an empty quest")
    func decodesEmptyRecord() throws {
        let quest = try QuestFixture.quest(fields: Data())
        #expect(quest.editorID == nil)
        #expect(quest.name == nil)
        #expect(quest.kind == .none)
        #expect(quest.stages.isEmpty)
        #expect(quest.objectives.isEmpty)
        #expect(quest.aliases.isEmpty)
        #expect(quest.skipped.isEmpty)
    }

    @Test("a truncated DNAM costs the field, not the record")
    func truncatedGeneralDataCostsOneField() throws {
        var fields = QuestFixture.editorID("Short")
        fields += ESMFixture.field("DNAM", Data([1, 0, 50]))
        fields += QuestFixture.stage(5)
        let quest = try QuestFixture.quest(fields: fields)

        #expect(quest.editorID == "Short")
        #expect(quest.flags.isEmpty)
        #expect(quest.priority == 0)
        #expect(quest.stages.map(\.index) == [5])
        #expect(quest.skipped.ranked.map(\.name) == ["malformed DNAM"])
    }

    @Test("an unmodelled subrecord is skipped and counted")
    func unknownSubrecordIsCounted() throws {
        var fields = QuestFixture.editorID("Legacy")
        fields += ESMFixture.field("SCHR", Data(count: 20))
        fields += ESMFixture.field("SCTX", ESMFixture.zstring("legacy script"))
        let quest = try QuestFixture.quest(fields: fields)

        #expect(quest.editorID == "Legacy")
        #expect(quest.skipped.total == 2)
        #expect(quest.skipped.ranked.map(\.name).sorted() == ["unknown SCHR", "unknown SCTX"])
    }

    // MARK: - Stage grouping

    @Test("log entries group under the stage that opened them")
    func groupsLogEntriesUnderTheirStage() throws {
        var fields = QuestFixture.stage(10)
        fields += QuestFixture.logEntry(text: "first")
        fields += QuestFixture.condition(functionIndex: 7)
        fields += QuestFixture.logEntry(text: "second")
        fields += QuestFixture.word("NAM0", 0x0200)
        fields += QuestFixture.stage(20)
        fields += QuestFixture.logEntry(text: "third")
        let quest = try QuestFixture.quest(fields: fields)

        #expect(quest.stages.count == 2)
        #expect(quest.stages[0].logEntries.count == 2)
        #expect(quest.stages[0].logEntries[0].text == .inline("first"))
        // The CTDA arrived while the first log entry was open, so it belongs
        // to that entry rather than to the quest's own condition run.
        #expect(quest.stages[0].logEntries[0].conditions.conditions.count == 1)
        #expect(quest.stages[0].logEntries[1].conditions.isEmpty)
        #expect(quest.stages[0].logEntries[1].nextQuest == FormID(0x0200))
        #expect(quest.stages[1].logEntries.count == 1)
        #expect(quest.dialogueConditions.isEmpty)
        #expect(quest.skipped.isEmpty)
    }

    @Test("a duplicate stage index keeps both stages")
    func keepsDuplicateStageIndices() throws {
        var fields = QuestFixture.stage(10)
        fields += QuestFixture.logEntry(text: "a")
        fields += QuestFixture.stage(10)
        fields += QuestFixture.logEntry(text: "b")
        let quest = try QuestFixture.quest(fields: fields)

        #expect(quest.stages.map(\.index) == [10, 10])
        #expect(quest.journalStages.count == 2)
        #expect(quest.skipped.isEmpty)
    }

    @Test("a log entry with no stage open costs itself")
    func orphanLogEntryCostsOneEntry() throws {
        var fields = QuestFixture.logEntry(text: "orphan")
        fields += QuestFixture.word("NAM0", 0x0300)
        fields += QuestFixture.stage(10)
        fields += QuestFixture.logEntry(text: "kept")
        let quest = try QuestFixture.quest(fields: fields)

        #expect(quest.stages.count == 1)
        #expect(quest.stages[0].logEntries.count == 1)
        #expect(quest.stages[0].logEntries[0].text == .inline("kept"))
        #expect(quest.skipped.ranked.map(\.name).sorted() == [
            "orphan CNAM", "orphan NAM0", "orphan QSDT"
        ])
    }

    // MARK: - Objective and target pairing

    @Test("targets pair with the objective that opened them")
    func pairsTargetsWithTheirObjective() throws {
        var fields = QuestFixture.objective(10, text: "one")
        fields += QuestFixture.target(alias: 1)
        fields += QuestFixture.condition(functionIndex: 11)
        fields += QuestFixture.target(alias: 2)
        fields += QuestFixture.objective(20, flags: 1, text: "two")
        fields += QuestFixture.target(alias: 3)
        let quest = try QuestFixture.quest(fields: fields)

        #expect(quest.objectives.map(\.index) == [10, 20])
        #expect(quest.objectives[0].targets.map(\.aliasID) == [1, 2])
        #expect(quest.objectives[0].targets[0].conditions.conditions.count == 1)
        #expect(quest.objectives[0].targets[1].conditions.isEmpty)
        #expect(quest.objectives[1].flags == [.oredWithPrevious])
        #expect(quest.objectives[1].targets.map(\.aliasID) == [3])
        #expect(quest.skipped.isEmpty)
    }

    @Test("a QSTA before any objective costs itself")
    func orphanTargetCostsOneEntry() throws {
        var fields = QuestFixture.target(alias: 9)
        fields += QuestFixture.objective(10, text: "kept")
        let quest = try QuestFixture.quest(fields: fields)

        #expect(quest.objectives.count == 1)
        #expect(quest.objectives[0].targets.isEmpty)
        #expect(quest.legacyTargets.isEmpty)
        #expect(quest.skipped.ranked.map(\.name) == ["orphan QSTA"])
    }

    @Test("ANAM ends the objective run, so the trailing NNAM is the description")
    func aliasMarkerEndsTheObjectiveRun() throws {
        var fields = QuestFixture.objective(10, text: "objective text")
        fields += QuestFixture.word("ANAM", 2)
        fields += ESMFixture.field("NNAM", ESMFixture.zstring("author notes"))
        fields += QuestFixture.target(alias: 0x0004_0000)
        let quest = try QuestFixture.quest(fields: fields)

        #expect(quest.objectives[0].displayText == .inline("objective text"))
        #expect(quest.questDescription == "author notes")
        // A QSTA after the alias run is a record-level legacy target, whose
        // word is a reference FormID rather than an alias ID.
        #expect(quest.legacyTargets.map(\.reference) == [FormID(0x0004_0000)])
        #expect(quest.skipped.isEmpty)
    }

    // MARK: - Helpers

    /// A four-character code as the little-endian word ENAM stores.
    private func fourCC(_ value: String) -> UInt32 {
        FourCC(stringLiteral: value).rawValue
    }
}
