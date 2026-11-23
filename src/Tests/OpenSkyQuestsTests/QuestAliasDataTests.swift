// The factions, spells, and items a reference gains and loses as it enters and
// leaves a quest alias (<https://ck.uesp.net/wiki/Quest_Alias_Tab>).

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
@Suite("Quest alias data")
struct QuestAliasDataTests {
    private let resolver = FormIDResolver(pluginName: "test.esm", masters: [])

    private func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "test.esm", objectID: objectID)
    }

    private func form(_ objectID: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: "test.esm", objectID: objectID)
    }

    private var follower: Quest.Alias {
        var alias = Quest.Alias(id: 0, category: .reference)
        alias.factions = [FormID(0x0700)]
        alias.spells = [FormID(0x0710)]
        alias.items = [Quest.AliasItem(item: FormID(0x0720), count: 2)]
        return alias
    }

    @Test func enteringGivesFactionsSpellsAndItems() {
        let changes = QuestAliasData.changes(
            aliases: [follower], resolver: resolver,
            old: .empty, new: QuestAliasState(fills: [.init(aliasID: 0, reference: key(0x0900))])
        )
        #expect(changes == [QuestAliasDataChange(
            reference: key(0x0900), entered: true, factions: [form(0x0700)],
            spells: [form(0x0710)], items: [.init(item: form(0x0720), count: 2)]
        )])
    }

    @Test func forcingToAnotherReferenceTakesFromTheFirstBeforeGivingTheSecond() {
        let changes = QuestAliasData.changes(
            aliases: [follower], resolver: resolver,
            old: QuestAliasState(fills: [.init(aliasID: 0, reference: key(0x0900))]),
            new: QuestAliasState(fills: [.init(aliasID: 0, reference: key(0x0901))])
        )
        #expect(changes.map(\.reference) == [key(0x0900), key(0x0901)])
        #expect(changes.map(\.entered) == [false, true])
        #expect(changes[0].items.isEmpty)
        #expect(changes[0].factions == [form(0x0700)])
    }

    @Test func anUnchangedOrDatalessAliasGivesNothing() {
        let filled = QuestAliasState(fills: [.init(aliasID: 0, reference: key(0x0900))])
        let plain = Quest.Alias(id: 0, category: .reference)
        #expect(QuestAliasData.changes(
            aliases: [follower], resolver: resolver, old: filled, new: filled
        ).isEmpty)
        #expect(QuestAliasData.changes(
            aliases: [plain], resolver: resolver, old: .empty, new: filled
        ).isEmpty)
    }

    @Test func theRuntimeReportsAForcedAliasAndTheStop() throws {
        let alias = QuestFixture.alias(
            id: 0, name: "Follower", flags: 2, fill: Data(),
            extras: QuestFixture.word("ALFC", 0x0700)
        )
        let quests = try QuestFixture.store(QuestFixture.record(
            formID: 0x0100,
            fields: QuestFixture.editorID("Followers") + QuestFixture.general() + alias
        ), pluginName: "test.esm")
        var runtime = QuestRuntime(store: WorldStateStore(), quests: quests)
        var reported: [QuestAliasDataChange] = []
        runtime.aliasDataChanged = { reported += $0 }
        try runtime.startQuest(FormID(0x0100))
        try runtime.forceAlias(0, to: key(0x0900), on: FormID(0x0100))
        try runtime.stopQuest(FormID(0x0100))
        #expect(reported.map(\.entered) == [true, false])
        #expect(reported
            .allSatisfy { $0.reference == key(0x0900) && $0.factions == [form(0x0700)] })
    }
}
