// Journal page model coverage (issue #184): which quests are listed, what a
// row says, and how selection behaves.
//
// Every quest is synthetic, built out of `QuestFixture` bytes, so nothing here
// reads game data. The fixture plugin is not localized, so its lstrings are
// inline and no string table is needed — which is also the unlocalized-mod
// path through `JournalMenuModel.text`.

import Foundation
@testable import opensky
import Testing

@MainActor
@Suite("Journal menu model")
struct JournalMenuModelTests {
    private let mainQuest = FormID(0x0100)
    private let sideQuest = FormID(0x0200)
    private let hiddenQuest = FormID(0x0300)

    /// Three quests: a start-game-enabled main quest with two stages and two
    /// objectives, a dormant side quest whose only stage is a start-up stage,
    /// and one of DNAM type 0, which never appears in a journal.
    private func store() throws -> QuestStore {
        try QuestFixture.store(
            QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("MQ101")
                    + QuestFixture.full("Unbound")
                    + QuestFixture.general(flags: 0x0001, type: 1)
                    + QuestFixture.stage(10)
                    + QuestFixture.logEntry(text: "A dragon attacked Helgen.")
                    + QuestFixture.stage(20)
                    + QuestFixture.logEntry(text: "I escaped through the keep.")
                    + QuestFixture.objective(10, text: "Escape Helgen")
                    + QuestFixture.objective(20, text: "Follow Hadvar")
            )
                + QuestFixture.record(
                    formID: 0x0200,
                    fields: QuestFixture.editorID("FreeformRiften")
                        + QuestFixture.full("Supply and Demand")
                        + QuestFixture.general(type: 6)
                        + QuestFixture.stage(5, flags: 0x02)
                        + QuestFixture.logEntry(text: "Someone wants a delivery.")
                        + QuestFixture.objective(5, text: "Deliver the parcel")
                )
                + QuestFixture.record(
                    formID: 0x0300,
                    fields: QuestFixture.editorID("HiddenController")
                        + QuestFixture.general(flags: 0x0001, type: 0)
                        + QuestFixture.stage(1)
                        + QuestFixture.logEntry(text: "never shown")
                )
        )
    }

    private func runtime() throws -> QuestRuntime {
        try QuestRuntime(store: WorldStateStore(), quests: store())
    }

    private func model(_ runtime: QuestRuntime) -> JournalMenuModel {
        JournalMenuModel.build(runtime: runtime, strings: nil)
    }

    // MARK: - Row set

    /// Only running or completed quests are listed, and a DNAM type-0 quest is
    /// never listed at all even while it runs.
    @Test
    func listsRunningJournalQuestsAndNeverTypeZero() throws {
        let runtime = try runtime()
        let built = model(runtime)
        #expect(built.active.map(\.editorID) == ["MQ101"])
        #expect(built.completed.isEmpty)
        // The hidden quest is start-game-enabled, so it *is* running.
        #expect(try runtime.state(of: hiddenQuest).isRunning)
        #expect(!built.active.contains { $0.editorID == "HiddenController" })
    }

    @Test
    func startingAQuestPutsItOnThePage() throws {
        let runtime = try runtime()
        try runtime.startQuest(sideQuest)
        #expect(model(runtime).active.map(\.editorID) == ["FreeformRiften", "MQ101"])
    }

    /// Completing does not stop a quest, so a completed running quest appears
    /// on both lists — which is what `QuestRuntimeState.completing` records.
    @Test
    func aCompletedRunningQuestIsOnBothLists() throws {
        let runtime = try runtime()
        try runtime.completeQuest(mainQuest)
        let built = model(runtime)
        #expect(built.active.map(\.editorID) == ["MQ101"])
        #expect(built.completed.map(\.editorID) == ["MQ101"])
        #expect(built.active.first?.isCompleted == true)
    }

    // MARK: - Row content

    @Test
    func aRowCarriesTheResolvedTitleTypeAndHighestStage() throws {
        let runtime = try runtime()
        try runtime.setStage(20, on: mainQuest)
        try runtime.setStage(10, on: mainQuest)
        let row = try #require(model(runtime).active.first)
        #expect(row.title == "Unbound")
        #expect(row.editorID == "MQ101")
        #expect(row.kind == .mainQuest)
        // Setting a lower stage afterwards never lowers the current stage.
        #expect(row.stage == 20)
    }

    /// A quest with no FULL falls back to its editor ID: a row with no label
    /// would be unselectable.
    @Test
    func aQuestWithoutANameFallsBackToItsEditorID() throws {
        let store = try QuestFixture.store(
            QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("NamelessQuest")
                    + QuestFixture.general(flags: 0x0001, type: 1)
            )
        )
        let runtime = QuestRuntime(store: WorldStateStore(), quests: store)
        #expect(model(runtime).active.first?.title == "NamelessQuest")
    }

    /// Only reached stages contribute journal paragraphs, oldest first, and the
    /// description block joins them the way the page shows them.
    @Test
    func logEntriesFollowTheReachedStagesInStageOrder() throws {
        let runtime = try runtime()
        try runtime.setStage(20, on: mainQuest)
        let partial = try #require(model(runtime).active.first)
        #expect(partial.logEntries == ["I escaped through the keep."])

        try runtime.setStage(10, on: mainQuest)
        let full = try #require(model(runtime).active.first)
        #expect(full.logEntries == [
            "A dragon attacked Helgen.", "I escaped through the keep."
        ])
        #expect(full.descriptionText.contains("\n\n"))
    }

    /// An untouched objective is not on the page; the three display flags map
    /// onto the three states, failed winning over completed.
    @Test
    func onlyTouchedObjectivesAppearAndFailedWins() throws {
        let runtime = try runtime()
        #expect(model(runtime).active.first?.objectives.isEmpty == true)

        try runtime.setObjectiveDisplayed(10, on: mainQuest)
        try runtime.setObjectiveCompleted(20, on: mainQuest)
        let shown = try #require(model(runtime).active.first)
        #expect(shown.objectives.map(\.index) == [10, 20])
        #expect(shown.objectives.map(\.text) == ["Escape Helgen", "Follow Hadvar"])
        #expect(shown.objectives.map(\.state) == [.displayed, .completed])

        try runtime.setObjectiveFailed(20, on: mainQuest)
        let failed = try #require(model(runtime).active.first)
        #expect(failed.objectives.last?.state == .failed)
    }

    // MARK: - Selection

    @Test
    func selectionClampsAndNeverWraps() throws {
        let runtime = try runtime()
        try runtime.startQuest(sideQuest)
        var built = model(runtime)
        #expect(built.selectedIndex == 0)

        built.moveSelection(by: -1)
        #expect(built.selectedIndex == 0)
        built.moveSelection(by: 1)
        #expect(built.selectedIndex == 1)
        built.moveSelection(by: 1)
        #expect(built.selectedIndex == 1)
        #expect(built.selectedEntry?.editorID == "MQ101")
    }

    /// An empty list holds the movie's own nothing-selected sentinel.
    @Test
    func anEmptyListSelectsNothing() throws {
        let runtime = try runtime()
        try runtime.stopQuest(mainQuest)
        let built = model(runtime)
        #expect(built.isEmpty)
        #expect(built.selectedIndex == -1)
        #expect(built.selectedEntry == nil)
    }

    @Test
    func switchingToCompletedReselectsIntoTheOtherList() throws {
        let runtime = try runtime()
        try runtime.startQuest(sideQuest)
        try runtime.completeQuest(sideQuest)
        var built = model(runtime)
        built.select(1)
        #expect(built.selectedEntry?.editorID == "MQ101")

        built.setShowsCompleted(true)
        #expect(built.showsCompleted)
        #expect(built.entries.map(\.editorID) == ["FreeformRiften"])
        #expect(built.selectedIndex == 0)
    }
}
