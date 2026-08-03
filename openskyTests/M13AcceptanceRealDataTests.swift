// M13 acceptance against the user's own read-only Skyrim SE install (issue
// #185): one vanilla quest walked end to end through its real scripts, with the
// fault, unimplemented-native and condition tallies pinned rather than
// described.
//
// The quest is `MGRArniel01`, chosen from the issue-#181 census shortlist and
// not from memory: it is the cheapest journal-visible quest in `Skyrim.esm` —
// two stages, one objective, one forced-reference alias, no conditions — and it
// is the same target `QuestScriptRealDataTests` and `JournalAcceptanceRealDataTests`
// already run against, so the three gates cannot drift onto different quests.
//
// Its stages are set from outside rather than by a dialogue INFO, which is the
// scope decision the issue asked for: `MGRArniel01` advances through dialogue,
// and no vanilla quest on the shortlist progresses without it, so the gate
// drives `SetStage` the way the sidebar's Quest Controls do and leaves the
// dialogue system to a later milestone. The synthetic half of the gate
// (`M13AcceptanceTests`) is what proves a *world event* can drive the same path.
//
// Nothing from the install is committed: the report goes to gitignored `logs/`
// and carries counts and editor IDs only — never journal text, never a script
// body. Run it with `make realtest T='M13AcceptanceRealDataTests/...'`, which
// supplies the data root and the RSS watchdog.

import Foundation
@testable import opensky
import Testing

struct M13AcceptanceRealDataTests {
    private static let targetEditorID = "MGRArniel01"
    private static let pluginName = "Skyrim.esm"
    private static let slot = "m13-acceptance-real"

    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil)) @MainActor
    func walksTheTargetQuestEndToEndAndResumesFromASave() throws {
        let root = try #require(Self.dataRoot)
        let session = try M13RealDataSession(root: root, pluginName: Self.pluginName)
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

        try M13RealDataReport.write(
            session: session, quest: quest, state: state, conditions: conditions
        )
    }

    // MARK: - Assertions

    /// The milestone's stated target: the quest's own scripts ran, reaching for
    /// no native OpenSky has not written, and the one fault they do produce is
    /// pinned and explained rather than tolerated as a number.
    ///
    /// That fault is `typeMismatch(expected: "Object", actual: "None")` at the
    /// first instruction of the quest's second fragment. This session loads no
    /// cell, so the five object properties on the fragment script resolve to no
    /// live handle and keep their compiler defaults — the five
    /// `unresolvedReference` binding skips below — and calling a method on one
    /// of them is a call on `None`. It is the absence of a world, not a quest
    /// bug: the synthetic gate, which does attach a cell, faults zero times.
    @MainActor
    private static func expectCleanRun(_ session: M13RealDataSession) throws {
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
        _ session: M13RealDataSession,
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
    /// The target quest declares no conditions of its own — the census says so —
    /// so what is proved here is that the four functions issue #182 registered
    /// resolve this quest and answer conclusively, which is what a condition
    /// elsewhere in the corpus asking about it would get.
    @MainActor
    private static func expectConditions(
        _ session: M13RealDataSession,
        quest: Quest
    ) throws -> ConditionTally {
        #expect(
            M13RealDataSession.conditionCount(of: quest) == 0,
            "the target quest grew conditions the census did not report"
        )
        var evaluator = try ConditionEvaluator(
            context: ConditionContext(quests: session.runtime.resolution())
        )
        for index in M13RealDataSession.questConditionIndices {
            let outcome = try evaluator.evaluate(ConditionEvaluatorFixture.condition(
                functionIndex: index, parameter1: quest.formID.rawValue
            ))
            #expect(outcome.isConclusive, "condition \(index) could not be answered")
        }
        #expect(evaluator.tally.unresolvedQuestTotal == 0)
        #expect(evaluator.tally.unknownFunctionTotal == 0)
        #expect(
            evaluator.tally.conditionsEvaluated
                == M13RealDataSession.questConditionIndices.count
        )
        return evaluator.tally
    }

    /// The save half: a real slot written mid-quest and restored into a brand
    /// new store, runtime and quest layer, producing the identical page.
    ///
    /// What is compared is the quest's own state, not the whole snapshot. On
    /// real data the load path legitimately materializes more than the file
    /// held: `attachRunningQuestScripts` fills the aliases of every quest
    /// `Skyrim.esm` flags start-game-enabled, so a restored store holds tables
    /// a store that only ever started one quest never had. Whole-snapshot
    /// equality is the synthetic gate's claim (`M13AcceptanceTests`), where the
    /// session defines exactly one quest and that difference cannot arise.
    @MainActor
    private static func expectSaveResumes(
        _ session: M13RealDataSession,
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

        let restored = try M13RealDataSession(root: session.root, pluginName: pluginName)
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
