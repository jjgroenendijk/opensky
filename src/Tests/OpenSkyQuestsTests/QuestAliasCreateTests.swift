// The "Create Reference to Object" alias fill over synthetic `QuestFixture` bytes.

import Foundation
import OpenSkyEngineTesting
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyQuests
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
@Suite("Quest alias creation")
struct QuestAliasCreateTests {
    private let quest = FormID(0x0100)
    private let marker = ReferenceKey.plugin(name: "test.esm", objectID: 0x0500)

    /// A marker alias, then an alias that creates base 0x0700 at it, or in it with
    /// `inside`.
    private func runtime(_ store: WorldStateStore, inside: Bool = false) throws -> QuestRuntime {
        let createAt: UInt32 = inside ? 0x8000 : 0
        let quests = try QuestFixture.store(QuestFixture.record(
            formID: 0x0100,
            fields: QuestFixture.editorID("MQ101")
                + QuestFixture.general(flags: 0, type: 1)
                + QuestFixture.stage(10, flags: 0x02)
                + QuestFixture.logEntry(text: "start")
                + QuestFixture.marker("ANAM")
                + QuestFixture.alias(
                    id: 0, name: "StartMarker", fill: QuestFixture.word("ALFR", 0x0500)
                )
                + QuestFixture.alias(
                    id: 1, name: "Headsman", fill: QuestFixture.word("ALCO", 0x0700),
                    extras: QuestFixture.word("ALCA", createAt)
                )
        ))
        return QuestRuntime(store: store, quests: quests)
    }

    @Test func aCreatedReferenceFillsItsAliasAtTheAnchor() throws {
        var quests = try runtime(WorldStateStore())
        var asked: [(FormID, ReferenceKey)] = []
        quests.referenceCreator = { base, anchor in
            asked.append((base, anchor))
            return .generated(7)
        }
        try quests.startQuest(quest)
        #expect(asked.map(\.0) == [FormID(0x0700)])
        #expect(asked.map(\.1) == [marker])
        #expect(quests.aliasReference(alias: 1, in: quest) == .generated(7))
    }

    @Test func withoutACreatorTheAliasStaysEmptyAndTheQuestStarts() throws {
        let quests = try runtime(WorldStateStore())
        try quests.startQuest(quest)
        #expect(try quests.state(of: quest).isRunning)
        #expect(quests.aliasReference(alias: 1, in: quest) == nil)
    }

    @Test func createInIsATalliedSkip() throws {
        let quests = try runtime(WorldStateStore(), inside: true)
        let record = try #require(quests.quests.quest(quest))
        let result = QuestAliasFiller.fill(record, resolver: quests.quests.resolver)
        #expect(result.creations.isEmpty)
        #expect(result.skipped.counts[.unsupportedFillType(.createReferenceToObject)] == 1)
    }
}
