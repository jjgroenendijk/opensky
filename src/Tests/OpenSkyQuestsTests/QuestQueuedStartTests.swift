// The start a script asks for: queued, then prepared, then start-up, then running,
// with what a script reads in each phase. Quests come from `QuestFixture`.

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
@Suite("Quest queued start")
struct QuestQueuedStartTests {
    private let first = FormID(0x0100)
    private let second = FormID(0x0200)

    private func runtime() throws -> QuestRuntime {
        try QuestRuntime(store: WorldStateStore(), quests: QuestFixture.store(
            QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("First") + QuestFixture.general(type: 1)
                    + QuestFixture.stage(10) + QuestFixture.logEntry(text: "ten")
                    + QuestFixture.objective(10, text: "Go")
            ) + QuestFixture.record(
                formID: 0x0200,
                fields: QuestFixture.editorID("Second") + QuestFixture.general(type: 1)
            )
        ))
    }

    @Test func aQueuedQuestStaysStoppedForScripts() throws {
        let quests = try runtime()
        let state = try quests.queueStart(first, stage: nil, objective: nil)
        #expect(state.start.phase == .queued)
        #expect(!state.reportsRunning && !state.isStarting && state.reportsStopped)
        #expect(state.awaitsStart)
        #expect(quests.pendingStarts().map(\.quest.formID) == [first])
    }

    @Test func theOldestRequestComesFirstAndASecondCallKeepsItsPlace() throws {
        let quests = try runtime()
        try quests.queueStart(second, stage: nil, objective: nil)
        try quests.queueStart(first, stage: nil, objective: nil)
        let again = try quests.queueStart(second, stage: 10, objective: 10)
        #expect(again.start.stages == [10] && again.start.objectives == [10])
        #expect(quests.pendingStarts().map(\.quest.formID) == [second, first])
    }

    @Test func preparingResetsTheQuestAndStartUpRunsItInside() throws {
        let quests = try runtime()
        try quests.setStage(10, on: first)
        try quests.setObjectiveDisplayed(10, on: first)
        try quests.completeQuest(first)
        try quests.stopQuest(first)
        #expect(try quests.state(of: first).isStageDone(10))

        try quests.queueStart(first, stage: nil, objective: nil)
        let prepared = try quests.prepareStart(first)
        #expect(prepared.start.phase == .prepared)
        #expect(prepared.stagesReached.isEmpty && prepared.objectives.isEmpty)
        #expect(!prepared.isCompleted && !prepared.isRunning)
        #expect(prepared.isStarting && !prepared.reportsStopped)

        let startUp = try quests.beginStartUp(first)
        #expect(startUp.isRunning && !startUp.reportsRunning && startUp.isStarting)

        let running = try quests.finishStart(first)
        #expect(running.reportsRunning && !running.isStarting && running.start.hasRun)
        #expect(quests.pendingStarts().isEmpty)
    }

    @Test func aStopDuringStartUpEndsTheStart() throws {
        let quests = try runtime()
        try quests.queueStart(first, stage: nil, objective: nil)
        try quests.prepareStart(first)
        try quests.beginStartUp(first)
        let stopped = try quests.stopQuest(first)
        #expect(stopped.start.phase == .idle && stopped.reportsStopped && stopped.start.hasRun)
    }

    @Test func aRequiredAliasThatStaysEmptyDropsTheRequest() throws {
        let alias = QuestFixture.alias(
            id: 0, name: "Missing", fill: QuestFixture.word("ALFR", 0)
        )
        let quests = try QuestRuntime(store: WorldStateStore(), quests: QuestFixture.store(
            QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("First") + QuestFixture.marker("ANAM") + alias
            )
        ))
        try quests.queueStart(first, stage: nil, objective: nil)
        #expect(throws: QuestError.self) { try quests.prepareStart(first) }
        let state = try quests.state(of: first)
        #expect(state.start.phase == .idle && !state.start.hasRun)
        #expect(quests.pendingStarts().isEmpty)
    }
}
