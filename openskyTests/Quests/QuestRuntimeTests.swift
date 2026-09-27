// Quest runtime state and its mutation API (issue #182): baselines, the typed
// failures, `setStage` idempotence, journalling and snapshot determinism.
//
// Every quest is synthetic, built out of `QuestFixture` bytes, so nothing here
// reads game data. The store is @MainActor, so the suite is too.

import Foundation
@testable import opensky
import Testing

@MainActor
@Suite("Quest runtime")
struct QuestRuntimeTests {
    private let mainQuest = FormID(0x0100)
    private let sideQuest = FormID(0x0200)

    /// Two quests: a start-game-enabled one with three stages (one of them a
    /// shut-down stage) and two objectives, and a dormant one whose only stage
    /// is flagged start-up.
    private func store() throws -> QuestStore {
        try QuestFixture.store(
            QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("MQ101")
                    + QuestFixture.general(flags: 0x0001, type: 1)
                    + QuestFixture.stage(10)
                    + QuestFixture.logEntry(text: "start")
                    + QuestFixture.stage(20)
                    + QuestFixture.logEntry(text: "middle")
                    + QuestFixture.stage(200, flags: 0x04)
                    + QuestFixture.logEntry(text: "end")
                    + QuestFixture.objective(10, text: "Find the horn")
                    + QuestFixture.objective(20, text: "Return the horn")
            )
                + QuestFixture.record(
                    formID: 0x0200,
                    fields: QuestFixture.editorID("FreeformRiften")
                        + QuestFixture.general(type: 6)
                        + QuestFixture.stage(5, flags: 0x02)
                        + QuestFixture.logEntry(text: "begin")
                        + QuestFixture.objective(5, text: "Steal the ring")
                )
        )
    }

    private func runtime(_ store: WorldStateStore = WorldStateStore()) throws -> QuestRuntime {
        try QuestRuntime(store: store, quests: self.store())
    }

    // MARK: - Baselines

    /// A start-game-enabled quest reports running without ever being touched,
    /// and stays clean while it does.
    @Test func startGameEnabledQuestsRunFromTheirBaseline() throws {
        let store = WorldStateStore()
        let quests = try runtime(store)
        let baseline = try quests.state(of: mainQuest)
        #expect(baseline.isRunning)
        #expect(!baseline.isCompleted)
        #expect(baseline.stagesReached.isEmpty)
        #expect(baseline.currentStage == nil)
        #expect(baseline.stageValue == 0)
        #expect(!quests.hasRuntimeState(mainQuest))
        #expect(store.dirtyCount == 0)

        #expect(try !quests.state(of: sideQuest).isRunning)
        #expect(try quests.state(editorID: "freeformriften").isRunning == false)
    }

    /// The first mutation materializes the baseline rather than recording a
    /// delta against it: the stored component still says the quest is running.
    @Test func firstMutationMaterializesTheBaseline() throws {
        let store = WorldStateStore()
        let quests = try runtime(store)
        try quests.setObjectiveDisplayed(10, on: mainQuest)
        let state = try #require(store.component(QuestRuntimeState.self, for: key(0x0100)))
        #expect(state.isRunning)
        #expect(state.objective(10).isDisplayed)
        #expect(quests.hasRuntimeState(mainQuest))
    }

    // MARK: - Running state

    @Test func startAndStopMoveTheRunningFlagOnly() throws {
        let quests = try runtime()
        let started = try quests.startQuest(sideQuest)
        #expect(started.isRunning)
        try quests.setStage(5, on: sideQuest)
        let stopped = try quests.stopQuest(sideQuest)
        #expect(!stopped.isRunning)
        // Stopping is not resetting: the reached stage survives.
        #expect(stopped.stagesReached == [5])
        // Stopping something already stopped is a no-op rather than a failure.
        #expect(try !quests.stopQuest(sideQuest).isRunning)
    }

    /// `CompleteQuest()` flags completion and leaves the quest running.
    @Test func completingLeavesTheQuestRunning() throws {
        let quests = try runtime()
        let completed = try quests.completeQuest(mainQuest)
        #expect(completed.isCompleted)
        #expect(completed.isRunning)
    }

    // MARK: - Stages

    /// The documented `IsStageDone` rules: only visited stages are done, the
    /// current stage is the highest visited one, and a lower stage set later
    /// does not move it.
    @Test func stagesRecordVisitsRatherThanAHighWaterMark() throws {
        let quests = try runtime()
        try quests.setStage(20, on: mainQuest)
        let state = try quests.setStage(10, on: mainQuest)
        #expect(state.stagesReached == [10, 20])
        #expect(state.currentStage == 20)
        #expect(state.stageValue == 20)
        #expect(state.isStageDone(10))
        #expect(state.isStageDone(20))
        #expect(!state.isStageDone(15))
    }

    /// Setting a stage that was already reached changes nothing at all, so the
    /// store records no second journal entry for it.
    @Test func settingTheSameStageTwiceIsIdempotent() throws {
        let store = WorldStateStore()
        let quests = try runtime(store)
        let first = try quests.setStage(10, on: mainQuest)
        let entriesAfterFirst = store.journalEntries.count
        let second = try quests.setStage(10, on: mainQuest)
        #expect(first == second)
        #expect(store.journalEntries.count == entriesAfterFirst)
    }

    /// A stage flagged `startUpStage` is the one way to advance a quest that is
    /// not running, and one flagged `shutDownStage` stops it again.
    @Test func stageFlagsStartAndStopTheQuest() throws {
        let quests = try runtime()
        let started = try quests.setStage(5, on: sideQuest)
        #expect(started.isRunning)
        #expect(started.stagesReached == [5])

        let ended = try quests.setStage(200, on: mainQuest)
        #expect(!ended.isRunning)
        #expect(ended.isStageDone(200))
    }

    // MARK: - Objectives

    @Test func objectiveFlagsAreIndependentAndClearBackToUntouched() throws {
        let quests = try runtime()
        try quests.setObjectiveDisplayed(10, on: mainQuest)
        let both = try quests.setObjectiveCompleted(10, on: mainQuest)
        #expect(both.objective(10).isDisplayed)
        #expect(both.objective(10).isCompleted)
        #expect(!both.objective(10).isFailed)
        #expect(both.objectives.count == 1)

        try quests.setObjectiveDisplayed(10, false, on: mainQuest)
        let cleared = try quests.setObjectiveCompleted(10, false, on: mainQuest)
        // An untouched objective is not stored, so the table empties out.
        #expect(cleared.objectives.isEmpty)
        #expect(!cleared.objective(10).isCompleted)
    }

    @Test func objectivesStaySortedByIndex() throws {
        let quests = try runtime()
        try quests.setObjectiveDisplayed(20, on: mainQuest)
        let state = try quests.setObjectiveFailed(10, on: mainQuest)
        #expect(state.objectives.map(\.index) == [10, 20])
    }

    // MARK: - Typed failures

    @Test func unknownQuestsAndStagesAndObjectivesAreTypedFailures() throws {
        let quests = try runtime()
        #expect(throws: QuestError.unknownQuest(FormID(0x9999))) {
            try quests.state(of: FormID(0x9999))
        }
        #expect(throws: QuestError.unknownStage(quest: mainQuest, stage: 15)) {
            try quests.setStage(15, on: mainQuest)
        }
        #expect(throws: QuestError.unknownObjective(quest: mainQuest, objective: 99)) {
            try quests.setObjectiveDisplayed(99, on: mainQuest)
        }
    }

    /// Every mutation that only means something on a running quest refuses to
    /// run on a stopped one, and writes nothing when it refuses.
    @Test func mutatingAStoppedQuestFailsAndWritesNothing() throws {
        let store = WorldStateStore()
        let quests = try runtime(store)
        #expect(throws: QuestError.questNotRunning(sideQuest)) {
            try quests.completeQuest(sideQuest)
        }
        #expect(throws: QuestError.questNotRunning(sideQuest)) {
            try quests.setObjectiveDisplayed(5, on: sideQuest)
        }
        // Stage 20 of the main quest is an ordinary stage, so stopping the
        // quest first makes even a known stage refuse.
        try quests.stopQuest(mainQuest)
        #expect(throws: QuestError.questNotRunning(mainQuest)) {
            try quests.setStage(20, on: mainQuest)
        }
        #expect(store.component(QuestRuntimeState.self, for: key(0x0200)) == nil)
        #expect(try quests.state(of: mainQuest).stagesReached.isEmpty)
    }

    // MARK: - Journal, snapshot and reset

    @Test func mutationsJournalOldAndNewValues() throws {
        let store = WorldStateStore()
        let quests = try runtime(store)
        try quests.setStage(10, on: mainQuest)
        try quests.setStage(20, on: mainQuest)

        let entries = store.journalEntries.filter { $0.kind == .quest }
        #expect(entries.count == 2)
        // The first write materializes the baseline, so it has no old value.
        #expect(entries[0].oldValue == nil)
        #expect(entries[0].newValue == QuestRuntimeState(
            isRunning: true, stagesReached: [10]
        ).erased)
        #expect(entries[1].oldValue == entries[0].newValue)
        #expect(entries[1].newValue == QuestRuntimeState(
            isRunning: true, stagesReached: [10, 20]
        ).erased)
        #expect(entries.allSatisfy { $0.cell == nil })
    }

    /// The M10 two-stores pattern: the same end state reached in different
    /// mutation orders snapshots identically.
    @Test func snapshotsAreIndependentOfMutationOrder() throws {
        let ascending = WorldStateStore()
        let first = try runtime(ascending)
        try first.setStage(10, on: mainQuest)
        try first.setStage(20, on: mainQuest)
        try first.setObjectiveDisplayed(10, on: mainQuest)
        try first.setObjectiveCompleted(20, on: mainQuest)

        let descending = WorldStateStore()
        let second = try runtime(descending)
        try second.setObjectiveCompleted(20, on: mainQuest)
        try second.setObjectiveDisplayed(10, on: mainQuest)
        try second.setStage(20, on: mainQuest)
        try second.setStage(10, on: mainQuest)

        #expect(ascending.snapshot() == descending.snapshot())
    }

    @Test func resetDropsRuntimeStateBackToTheBaseline() throws {
        let store = WorldStateStore()
        let quests = try runtime(store)
        try quests.setStage(10, on: mainQuest)
        #expect(quests.reset(mainQuest))
        #expect(!quests.hasRuntimeState(mainQuest))
        #expect(store.dirtyCount == 0)
        #expect(try quests.state(of: mainQuest).isRunning)
        #expect(try quests.state(of: mainQuest).stagesReached.isEmpty)
        // Nothing to drop the second time.
        #expect(!quests.reset(mainQuest))
        #expect(!quests.reset(FormID(0x9999)))
    }

    @Test func runtimeQuestsListsOnlyTouchedQuests() throws {
        let quests = try runtime()
        #expect(quests.runtimeQuests().isEmpty)
        try quests.setStage(10, on: mainQuest)
        let listed = quests.runtimeQuests()
        #expect(listed.map(\.quest.editorID) == ["MQ101"])
        #expect(listed.first?.state.stagesReached == [10])
    }

    // MARK: - Resolution seam

    @Test func resolutionAnswersFromOverridesThenBaselines() throws {
        let store = WorldStateStore()
        let quests = try runtime(store)
        try quests.setStage(20, on: mainQuest)
        let resolution = quests.resolution()
        #expect(resolution.runtimeStateCount == 1)
        #expect(resolution.hasRuntimeState(mainQuest))
        #expect(resolution.state(for: mainQuest)?.stageValue == 20)
        // Untouched: the baseline, not nil.
        #expect(!resolution.hasRuntimeState(sideQuest))
        #expect(resolution.state(for: sideQuest)?.isRunning == false)
        #expect(resolution.state(editorID: "MQ101")?.stageValue == 20)
        #expect(resolution.state(for: FormID(0x9999)) == nil)
        #expect(QuestResolution.empty.state(for: mainQuest) == nil)
    }

    /// A resolution built off a snapshot answers the same way as one built off
    /// the live store, which is what lets a build thread evaluate conditions.
    @Test func resolutionOverASnapshotMatchesTheLiveStore() throws {
        let store = WorldStateStore()
        let quests = try runtime(store)
        try quests.setStage(20, on: mainQuest)
        let overSnapshot = try QuestResolution(defaults: self.store(), snapshot: store.snapshot())
        #expect(overSnapshot.state(for: mainQuest) == quests.resolution().state(for: mainQuest))
    }

    private func key(_ objectID: UInt32) -> ReferenceKey {
        GlobalFixture.key(objectID)
    }
}
