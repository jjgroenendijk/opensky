// What a stage's items do when the stage is set: every passing item writes the log
// entry, Complete Quest completes, and Fail Quest fails the quest and its objectives.

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
@Suite("Quest stage items")
struct QuestStageItemTests {
    private let quest = FormID(0x0100)

    private func runtime() throws -> QuestRuntime {
        var fields: Data = QuestFixture.editorID("Items")
        fields += QuestFixture.general(flags: 0x0001, type: 1)
        fields += QuestFixture.stage(10)
        fields += QuestFixture.logEntry(text: "first")
        fields += QuestFixture.logEntry(text: "second")
        fields += QuestFixture.stage(20)
        fields += QuestFixture.logEntry(flags: 0x01, text: "done")
        fields += QuestFixture.stage(30)
        fields += QuestFixture.logEntry(flags: 0x02, text: "lost")
        fields += QuestFixture.objective(10)
        fields += QuestFixture.objective(20)
        let record = QuestFixture.record(formID: 0x0100, fields: fields)
        return try QuestRuntime(store: WorldStateStore(), quests: QuestFixture.store(record))
    }

    @Test func everyPassingItemWritesTheLogEntry() throws {
        let quests = try runtime()
        let state = try quests.setStage(10, on: quest)
        #expect(state.journalLog == QuestJournalLog(stage: 10, items: [0, 1]))
        let chosen = try runtime().setStage(10, on: quest, items: [1])
        #expect(chosen.journalLog == QuestJournalLog(stage: 10, items: [1]))
    }

    @Test func aCompleteQuestItemCompletesTheQuest() throws {
        let quests = try runtime()
        try quests.setStage(10, on: quest)
        let state = try quests.setStage(20, on: quest)
        #expect(state.isCompleted)
        #expect(state.journalLog?.stage == 20)
        #expect(quests.store.miscStats.value("Quests Completed") == 1)
    }

    /// Fail Quest fails the quest and every shown objective, a completed one too.
    @Test func aFailQuestItemFailsTheQuestAndItsObjectives() throws {
        let quests = try runtime()
        try quests.setObjectiveDisplayed(10, on: quest)
        try quests.setObjectiveCompleted(20, on: quest)
        let state = try quests.setStage(30, on: quest)
        #expect(state.isFailed)
        #expect(!state.isCompleted)
        let allFailed = state.objectives.allSatisfy(\.isFailed)
        #expect(allFailed)
        #expect(state.objectives.count == 2)
    }

    /// Setting a reached stage again applies nothing a second time.
    @Test func aReachedStageAppliesItsItemsOnce() throws {
        let quests = try runtime()
        try quests.setStage(10, on: quest)
        try quests.setStage(20, on: quest)
        let again = try quests.setStage(10, on: quest)
        #expect(again.journalLog?.stage == 20)
    }

    @Test func failAllObjectivesFailsCompletedOnesToo() throws {
        let quests = try runtime()
        try quests.setObjectiveDisplayed(10, on: quest)
        try quests.setObjectiveCompleted(20, on: quest)
        let state = try quests.failAllObjectives(on: quest)
        #expect(state.objectives.map(\.isFailed) == [true, true])
        #expect(!state.isFailed)
    }

    /// With no conditions every item applies; otherwise the first.
    @Test func defaultItemsAreTheUnconditionedOnes() throws {
        let stage = try #require(try runtime().quests.quest(quest)?.stages.first)
        #expect(stage.defaultItems == [0, 1])
    }
}
