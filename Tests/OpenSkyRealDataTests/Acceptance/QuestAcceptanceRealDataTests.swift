// M13 acceptance on the user's install: `MGRArniel01` walked end to end through
// its real scripts, with the fault, native and condition tallies pinned. It is
// the cheapest journal-visible quest and the same target as the other quest
// gates. Stages are set from outside, as the Quest Controls do, because it
// advances through dialogue. The report goes to gitignored `logs/` and holds
// counts and editor IDs only. Run with `make realtest T='QuestAcceptanceRealDataTests/...'`.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMenus
@testable import OpenSkyQuestsInterface
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyScripting
@testable import OpenSkyScriptingInterface
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import TagsTesting
import Testing

@Suite(.tags(.acceptance))
struct QuestAcceptanceRealDataTests {
    private static let targetEditorID = "MGRArniel01"
    private static let pluginName = "Skyrim.esm"
    private static let slot = "m13-acceptance-real"

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot)) @MainActor
    func walksTheTargetQuestEndToEndAndResumesFromASave() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let session = try QuestRealDataSession(root: root, pluginName: Self.pluginName)
        let quest = try #require(session.quests.quest(editorID: Self.targetEditorID))
        let key = try #require(session.quests.key(for: quest.formID))

        try session.walk(quest: quest, key: key)
        let state = try session.state(of: quest.formID)
        #expect(state.isRunning)
        #expect(state.isCompleted)
        #expect(state.stagesReached == quest.stages.map(\.index).sorted())

        try Self.expectCleanRun(session)
        let page = try Self.expectJournal(session, quest: quest)
        let conditions = try Self.expectConditions(session, quest: quest)
        try Self.expectSaveResumes(session, page: page)

        try QuestRealDataReport.write(
            session: session, quest: quest, state: state, conditions: conditions
        )
    }

    // MARK: - Assertions

    /// The quest's own scripts ran without reaching for a missing native. The one
    /// fault is pinned: `typeMismatch(expected: "Object", actual: "None")` in the
    /// second fragment. No cell is loaded, so its five object properties stay
    /// `None` (the five `unresolvedReference` skips below). The synthetic gate,
    /// which attaches a cell, faults zero times.
    @MainActor
    private static func expectCleanRun(_ session: QuestRealDataSession) throws {
        let world = session.world
        #expect(world.questCount == 1)
        #expect(world.runtime.tally.faultTotal == 1)
        #expect(world.runtime.tally.faultKindCounts == ["typeMismatch": 1])
        #expect(world.bindingSkips.counts[.unresolvedReference] == 5)
        #expect(world.bindingSkips.counts[.aliasObject] == nil)
        #expect(world.runtime.tally.unimplementedNativeTotal == 0)
        #expect(world.questFragmentsQueued > 0, "no stage fragment ever ran")
        #expect(world.eventQueue.isEmpty, "the quest left work queued")
        // The quest's one alias filled, which is what its scripts and its
        // journal text read through.
        #expect(world.aliasResolution.filledAliasCount == 1)
    }

    /// The journal page the run produced: a title, an objective and at least
    /// one journal paragraph, all resolved from the plugin's own tables.
    ///
    /// The text itself is asserted for non-emptiness only and never written
    /// anywhere — it is the plugin's copyrighted string data.
    @MainActor
    private static func expectJournal(
        _ session: QuestRealDataSession,
        quest: Quest
    ) throws -> JournalQuestEntry {
        let model = try session.journal()
        let row = try #require(
            model.entries.first { $0.editorID == targetEditorID },
            "the target quest is not on the journal page"
        )
        #expect(!row.title.isEmpty)
        #expect(row.title != row.editorID, "the quest title never resolved from .strings")
        #expect(row.kind != Quest.Kind.none)
        #expect(row.stage == quest.stages.map(\.index).max())
        #expect(row.objectives.count == quest.objectives.count)
        #expect(row.objectives.allSatisfy { !$0.text.isEmpty })
        #expect(row.objectives.allSatisfy { $0.state == .completed })
        #expect(!row.logEntries.isEmpty, "no reached stage produced journal text")
        #expect(row.logEntries.allSatisfy { !$0.isEmpty })
        return row
    }

    /// The quest condition functions answered against live state on real data.
    /// The quest declares no conditions, so this proves the four quest functions
    /// resolve it and answer conclusively.
    @MainActor
    private static func expectConditions(
        _ session: QuestRealDataSession,
        quest: Quest
    ) throws -> ConditionTally {
        #expect(
            QuestRealDataSession.conditionCount(of: quest) == 0,
            "the target quest grew conditions the census did not report"
        )
        var evaluator = try ConditionEvaluator(
            context: ConditionContext(quests: session.runtime.resolution())
        )
        for index in QuestRealDataSession.questConditionIndices {
            let outcome = try evaluator.evaluate(ConditionEvaluatorFixture.condition(
                functionIndex: index, parameter1: quest.formID.rawValue
            ))
            #expect(outcome.isConclusive, "condition \(index) could not be answered")
        }
        #expect(evaluator.tally.unresolvedQuestTotal == 0)
        #expect(evaluator.tally.unknownFunctionTotal == 0)
        #expect(
            evaluator.tally.conditionsEvaluated
                == QuestRealDataSession.questConditionIndices.count
        )
        return evaluator.tally
    }

    /// A slot written mid-quest and restored into a new store produces the same
    /// page. Only the quest's own state is compared: on load,
    /// `attachRunningQuestScripts` fills the aliases of every start-game-enabled
    /// quest, so a restored store holds more tables than the one saved.
    @MainActor
    private static func expectSaveResumes(
        _ session: QuestRealDataSession,
        page: JournalQuestEntry
    ) throws {
        let directory = URL.temporaryDirectory.appending(path: "opensky-m13-real-tests")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let saves = OpenSkySaveStore(directory: directory)
        try saves.save(
            snapshot: session.worldState.snapshot(),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            scripts: session.world.instanceStates(),
            toSlot: slot
        )
        let file = try saves.load(slot: slot)

        let restored = try QuestRealDataSession(root: session.root, pluginName: pluginName)
        restored.worldState.restore(from: file.snapshot)
        restored.bridge.attachRunningQuestScripts()
        restored.world.restore(instanceStates: file.scripts)

        let key = try #require(session.quests.key(editorID: targetEditorID))
        #expect(
            restored.worldState.component(QuestRuntimeState.self, for: key)
                == session.worldState.component(QuestRuntimeState.self, for: key)
        )
        #expect(
            restored.worldState.component(QuestAliasState.self, for: key)
                == session.worldState.component(QuestAliasState.self, for: key)
        )
        #expect(restored.world.skips.counts[.unknownSaveScript] == nil)
        let restoredRow = try #require(
            restored.journal().entries.first { $0.editorID == targetEditorID }
        )
        #expect(restoredRow == page)
    }
}
