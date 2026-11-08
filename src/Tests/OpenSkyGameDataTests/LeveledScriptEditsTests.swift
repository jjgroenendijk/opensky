// What scripts change about leveled lists, read through the shared roller: added entries
// and `LVLG` global values. Rules: docs/engine/leveled-lists.md#script-changes.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct LeveledScriptEditsTests {
    private static let global = FormID(0xAA)

    /// A use-all `LVLI` with one entry and an `LVLG` global.
    private static func useAllList() throws -> LeveledList {
        var global = Data()
        global.appendUInt32(Self.global.rawValue)
        let fields = ESMFixture.field("LVLF", Data([0x04]))
            + ESMFixture.field("LVLG", global)
            + ESMFixture.field(
                "LVLO", ShoutFixture.leveledEntry(level: 1, reference: 0x10, count: 1)
            )
        return try LeveledList(record: ShoutFixture.record(type: "LVLI", fields: fields))
    }

    @Test func anAddedEntryRollsAfterThePluginEntries() throws {
        let edits = LeveledScriptEdits()
        let roller = LeveledListRoller(scriptEdits: edits)
        let list = try Self.useAllList()
        let before = roller.roll(forActor: FormID(0x1)).revision
        edits.setAddedEntries([list.formID: [
            LeveledList.Entry(addedForm: FormID(0x20), level: 1, count: 3)
        ]])
        let picks = roller.roll(
            list,
            count: 1,
            request: LeveledRequest(level: 5, playerLevel: 5),
            seed: 0
        )
        #expect(picks.map(\.entry.reference.rawValue) == [0x10, 0x20])
        #expect(picks.last?.count == 3)
        #expect(roller.roll(forActor: FormID(0x1)).revision > before)
    }

    @Test func aScriptValueOfTheGlobalWinsOverThePluginValue() throws {
        let edits = LeveledScriptEdits()
        let roller = LeveledListRoller(scriptEdits: edits, chanceNoneGlobal: { _ in 0 })
        let list = try Self.useAllList()
        #expect(roller.chanceNone(of: list) == 0)
        let revision = edits.revision
        edits.setGlobals([Self.global: 100])
        #expect(roller.chanceNone(of: list) == 100)
        #expect(edits.revision == revision + 1)
    }

    @Test func aWriteToAnUnreadGlobalKeepsTheRevision() {
        let edits = LeveledScriptEdits()
        edits.setGlobals([FormID(0xBB): 5])
        #expect(edits.revision == 0)
    }
}
