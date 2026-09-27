// QuestStore: the immutable QUST index, built from a synthetic plugin.
// See docs/formats/records.md.

import Foundation
@testable import opensky
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

    /// The Papyrus side arrives holding a `ReferenceKey` and has to name the
    /// record behind it, so the key index reads both ways (issue #322).
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
}
