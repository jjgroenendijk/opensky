// What the journal adds to quest state: a quest is tracked when it first shows an
// objective, and a completion counts the misc stats once.

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
@Suite("Quest journal state")
struct QuestJournalStateTests {
    private let main = FormID(0x0100)
    private let favour = FormID(0x0101)

    private func runtime() throws -> QuestRuntime {
        let quest = { (formID: UInt32, name: String, type: UInt32) in
            QuestFixture.record(
                formID: formID,
                fields: QuestFixture.editorID(name) + QuestFixture.general(type: type)
                    + QuestFixture.stage(10) + QuestFixture.objective(10)
                    + QuestFixture.objective(20) + QuestFixture.marker("ANAM")
            )
        }
        return try QuestRuntime(
            store: WorldStateStore(),
            quests: QuestFixture.store(quest(0x0100, "MainQuest", 1) + quest(0x0101, "Favour", 6))
        )
    }

    @Test func theFirstShownObjectiveTracksAQuestOnce() throws {
        let quests = try runtime()
        try quests.startQuest(main)
        #expect(!quests.isTracked(main))
        try quests.setObjectiveDisplayed(10, true, on: main)
        #expect(quests.isTracked(main))
        #expect(quests.trackedQuests().map(\.formID) == [main])
        quests.setTracked(main, false)
        try quests.setObjectiveDisplayed(20, true, on: main)
        #expect(!quests.isTracked(main), "an untracked quest stays untracked")
    }

    @Test func aCompletionCountsItsTypeOnce() throws {
        let quests = try runtime()
        try quests.startQuest(main)
        try quests.completeQuest(main)
        try quests.completeQuest(main)
        let stats = quests.store.miscStats
        #expect(stats.value("Quests Completed") == 1)
        #expect(stats.value("main quests completed") == 1)
    }

    @Test func aMiscQuestCountsItsObjectives() throws {
        let quests = try runtime()
        try quests.startQuest(favour)
        try quests.setObjectiveCompleted(10, true, on: favour)
        try quests.setObjectiveCompleted(10, true, on: favour)
        try quests.completeQuest(favour)
        let stats = quests.store.miscStats
        #expect(stats.value("Misc Objectives Completed") == 1)
        #expect(stats.value("Quests Completed") == 1)
        #expect(stats.values.count == 2, "a misc quest has no per-type stat")
    }

    @Test func aStatOutsideTheListIsRefused() {
        var stats = MiscStatsState()
        let unknown = stats.increment("Cheese Wheels Rolled")
        stats.increment("Bribes", by: .max)
        stats.increment("Bribes")
        #expect(!unknown)
        #expect(stats.values.count == 1)
        #expect(stats.value("Bribes") == .max, "a count saturates")
        #expect(MiscStats.catalog.count == 104, "the Creation Kit list has 104 names")
    }
}
