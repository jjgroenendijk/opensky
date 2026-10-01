// The journal readout rules, with plain values.

import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyQuests
import OpenSkyQuestsInterface
import Testing

@MainActor
struct JournalCoreTests {
    /// Failed outranks completed, and completed outranks displayed.
    @Test func objectiveWordsFollowTheFlagOrder() {
        #expect(JournalCore.objectiveWord(QuestObjectiveState(index: 1)) == "untouched")
        #expect(JournalCore.objectiveWord(QuestObjectiveState(index: 1, isDisplayed: true))
            == "displayed")
        #expect(JournalCore.objectiveWord(
            QuestObjectiveState(index: 1, isDisplayed: true, isCompleted: true)
        ) == "completed")
        #expect(JournalCore.objectiveWord(
            QuestObjectiveState(index: 1, isCompleted: true, isFailed: true)
        ) == "failed")
    }

    @Test func onlyRunningOrCompletedQuestsAreListed() throws {
        let runtime = try JournalCoordinatorTests.runtime()
        let entries = try runtime.quests.journalQuests().map {
            try JournalQuestStatus(quest: $0, state: runtime.state(of: $0.formID))
        }
        #expect(JournalCore.listed(entries).map(\.quest.editorID) == ["MQ101"])
    }

    /// Every declared objective is listed, touched or not.
    @Test func objectiveLinesCoverEveryDeclaredObjective() throws {
        let runtime = try JournalCoordinatorTests.runtime()
        let state = try runtime.setObjectiveDisplayed(20, true, on: FormID(0x0100))
        let quest = try #require(runtime.quests.quest(editorID: "MQ101"))
        let entry = JournalQuestStatus(quest: quest, state: state)
        #expect(JournalCore.objectiveLines(entry) == ["10 untouched", "20 displayed"])
        #expect(JournalCore.declaredStages(of: quest) == [10, 20])
    }
}
