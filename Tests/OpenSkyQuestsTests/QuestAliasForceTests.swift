// `ForceRefTo` and `Clear` at the quest runtime: one alias changes, the rest of the
// table stays, and an alias the quest does not define is refused.

import Foundation
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyQuests
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
@Suite("Quest alias forcing")
struct QuestAliasForceTests {
    private let quest = FormID(0x0100)

    private func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "test.esm", objectID: objectID)
    }

    private func runtime(_ store: WorldStateStore) throws -> QuestRuntime {
        let aliases = [(0, "Arniel", 0x0500), (1, "Book", 0x0501)].map { id, name, form in
            QuestFixture.alias(
                id: UInt32(id), name: name, flags: 0,
                fill: QuestFixture.word("ALFR", UInt32(form)), extras: Data()
            )
        }.reduce(Data(), +)
        let quests = try QuestFixture.store(QuestFixture.record(
            formID: 0x0100,
            fields: QuestFixture.editorID("MGRArniel01")
                + QuestFixture.general(flags: 0, type: 1) + aliases
        ))
        return QuestRuntime(store: store, quests: quests)
    }

    @Test func forcingMovesOneAliasAndClearingEmptiesIt() throws {
        let store = WorldStateStore()
        let quests = try runtime(store)
        try quests.startQuest(quest)

        try quests.forceAlias(0, to: key(0x0900), on: quest)
        #expect(quests.aliasReference(alias: 0, in: quest) == key(0x0900))
        #expect(quests.aliasReference(alias: 1, in: quest) == key(0x0501))

        try quests.forceAlias(0, to: nil, on: quest)
        try quests.forceAlias(1, to: nil, on: quest)
        #expect(try quests.aliasState(of: quest).isEmpty)
        #expect(store.component(QuestAliasState.self, for: key(0x0100)) == nil)
    }

    @Test func aLocationAliasIsForcedAndCleared() throws {
        let quests = try runtime(WorldStateStore())
        let location = ResolvedFormID(plugin: "test.esm", objectID: 0x0800)
        try quests.forceLocationAlias(1, to: location, on: quest)
        #expect(quests.aliasLocation(alias: 1, in: quest) == location)
        try quests.forceLocationAlias(1, to: nil, on: quest)
        #expect(quests.aliasLocation(alias: 1, in: quest) == nil)
    }

    @Test func anAliasTheQuestDoesNotDefineIsRefused() throws {
        let quests = try runtime(WorldStateStore())
        #expect(throws: QuestError.unknownAlias(quest: quest, alias: 7)) {
            try quests.forceAlias(7, to: key(0x0900), on: quest)
        }
        #expect(throws: QuestError.unknownQuest(FormID(0x0999))) {
            try quests.forceAlias(0, to: nil, on: FormID(0x0999))
        }
    }
}
