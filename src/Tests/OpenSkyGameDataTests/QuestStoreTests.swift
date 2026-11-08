// QuestStore: the immutable QUST index, built from a synthetic plugin.
// See docs/formats/quest-records.md.

import Foundation
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

@Suite("QUST store")
struct QuestStoreTests {
    @Test("indexes by FormID, editor ID and session key")
    func indexesEveryLookup() throws {
        let store = try QuestFixture.store(
            QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("MQ101")
                    + QuestFixture.general(type: 1)
                    + QuestFixture.stage(10)
                    + QuestFixture.logEntry(text: "start")
            )
                + QuestFixture.record(
                    formID: 0x0200,
                    fields: QuestFixture.editorID("FreeformRiften")
                        + QuestFixture.general(type: 6)
                )
        )

        #expect(store.count == 2)
        #expect(!store.isEmpty)
        #expect(store.skippedRecordCount == 0)
        #expect(store.quest(FormID(0x0100))?.editorID == "MQ101")
        #expect(store.quest(editorID: "mq101")?.formID == FormID(0x0100))
        #expect(store.formID(editorID: "FREEFORMRIFTEN") == FormID(0x0200))
        #expect(store.quest(FormID(0x0999)) == nil)
        #expect(store.quest(editorID: "absent") == nil)
        #expect(store.key(for: FormID(0x0100)) == GlobalFixture.key(0x0100))
        #expect(store.key(editorID: "mq101") == GlobalFixture.key(0x0100))
        #expect(store.key(editorID: "absent") == nil)
        #expect(store.sortedQuests().map(\.editorID) == ["FreeformRiften", "MQ101"])
        #expect(store.journalQuests().count == 2)
    }

    @Test("a quest of type none is indexed but never listed in the journal")
    func excludesNonJournalQuestsFromTheJournalList() throws {
        let store = try QuestFixture.store(
            QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("Hidden") + QuestFixture.general(type: 0)
            )
                + QuestFixture.record(
                    formID: 0x0200,
                    fields: QuestFixture.editorID("Shown") + QuestFixture.general(type: 8)
                )
        )
        #expect(store.count == 2)
        #expect(store.journalQuests().map(\.editorID) == ["Shown"])
    }

    /// Papyrus holds a `ReferenceKey` and must name the record behind it, so
    /// the key index reads both ways.
    @Test("session-stable keys resolve back to their quest")
    func resolvesKeysBackToQuests() throws {
        let store = try QuestFixture.store(
            QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("MQ101") + QuestFixture.general()
            )
                + QuestFixture.record(
                    formID: 0x0200,
                    fields: QuestFixture.editorID("FreeformRiften") + QuestFixture.general()
                )
        )
        let key = try #require(store.key(editorID: "mq101"))
        #expect(store.formID(for: key) == FormID(0x0100))
        #expect(store.quest(key: key)?.editorID == "MQ101")
        #expect(store.quest(key: GlobalFixture.key(0x9999)) == nil)
        #expect(store.formID(for: GlobalFixture.key(0x9999)) == nil)
    }

    @Test("an empty plugin yields an empty store")
    func handlesEmptyPlugin() throws {
        let store = try QuestFixture.store(Data())
        #expect(store.isEmpty)
        #expect(store.sortedQuests().isEmpty)
        #expect(QuestStore.empty.isEmpty)
    }

    /// `Extra.esm` writes its own quest under master index 1, but it loads third,
    /// so the store numbers it 0x02. A later plugin's override wins.
    @Test("a load-order store numbers every plugin's quests by load position")
    func numbersQuestsByLoadOrder() throws {
        let quest = { (formID: UInt32, editorID: String) in
            QuestFixture.record(
                formID: formID, fields: QuestFixture.editorID(editorID) + QuestFixture.general()
            )
        }
        let plugins = try [
            (name: "Base.esm", file: ESMFixture.plugin(records: [quest(0x0100, "BaseQuest")])),
            (
                name: "Patch.esm",
                file: ESMFixture.plugin(
                    masters: ["Base.esm"],
                    records: [quest(0x0100, "BaseQuestPatched"), quest(0x0100_0200, "PatchQuest")]
                )
            ),
            (
                name: "Extra.esm",
                file: ESMFixture.plugin(
                    masters: ["Base.esm"], records: [quest(0x0100_0300, "ExtraQuest")]
                )
            )
        ]
        let store = QuestStore(plugins: plugins)

        #expect(store.count == 3)
        #expect(store.quest(FormID(0x0100))?.editorID == "BaseQuestPatched")
        #expect(store.formID(editorID: "PatchQuest") == FormID(0x0100_0200))
        #expect(store.formID(editorID: "ExtraQuest") == FormID(0x0200_0300))
        #expect(store.quest(editorID: "ExtraQuest")?.formID == FormID(0x0200_0300))
        #expect(store.key(for: FormID(0x0200_0300)) == .plugin(name: "extra.esm", objectID: 0x300))
        #expect(store.sourcePlugin(of: FormID(0x0100)) == "Patch.esm")
        #expect(store.sourcePlugin(of: FormID(0x0200_0300)) == "Extra.esm")
        // FormIDs inside Extra.esm's record still use its own master list.
        let inner = store.sourceResolver(of: FormID(0x0200_0300)).resolve(FormID(0x0100_0400))
        #expect(inner == ResolvedFormID(plugin: "Extra.esm", objectID: 0x400))
        let resolved = ResolvedFormID(plugin: "Extra.esm", objectID: 0x300)
        #expect(store.resolver.localFormID(of: resolved) == FormID(0x0200_0300))
    }
}
