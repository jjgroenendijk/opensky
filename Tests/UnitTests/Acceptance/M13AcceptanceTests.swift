// M13 acceptance (issue #185): one quest, driven end to end by the world, with
// the journal following it and a mid-quest save resuming it.
//
// The gate statement in one run: the quest is running, a real M11 activation
// drives `SetStage` through script code, the stage fragment executes and mutates
// `WorldStateStore`, the alias resolves, the journal shows the quest's title,
// objective and log-entry text, and a save taken mid-quest loads into a fresh
// engine instance at the same stage with the same objectives and journal
// content.
//
// Every step asserts the trace and the accounting, not just that the call
// returned: which notes the VM dispatched in which order, which cell each write
// was attributed to, and what the journal model made of the result. The pixel
// half is `M13AcceptanceRenderTests` and the panel half is
// `M13AcceptancePanelTests`; both are gated, and everything here runs on a
// device-less runner with no install.

import Foundation
@testable import opensky
import Testing

@MainActor
struct M13AcceptanceTests {
    private typealias Chain = M13AcceptanceChain

    /// The slot the save/load step writes. Named for the gate so a stray file
    /// in a developer's saves directory says where it came from.
    private static let slot = "m13-acceptance"

    // MARK: - The loop

    /// The gate itself. One session walks the whole loop and every step is
    /// checked before the next one runs, so a failure names the step rather
    /// than leaving an end state to reverse-engineer.
    @Test("a real activation drives the quest through its fragment and into the journal")
    func theQuestLoopRunsEndToEnd() throws {
        let chain = try Chain()

        try Self.startTheQuest(chain)
        Self.attachTheLeversCell(chain)
        try Self.pullTheLever(chain)
        try Self.finishTheQuest(chain)
        try Self.resumeFromASave(chain)
    }

    // MARK: - Steps

    /// Step 1 — the quest starts. Its one alias fills, its two scripts and its
    /// alias script instantiate, and `OnInit` fires once on each.
    private static func startTheQuest(_ chain: Chain) throws {
        try chain.startQuest()

        let state = try chain.state
        #expect(state.isRunning)
        #expect(state.stagesReached.isEmpty)
        #expect(chain.notes.filter { $0 == "quest.oninit" }.count == 1)
        // The alias script ran, which is only possible on a filled alias: it is
        // keyed by the reference the alias holds, not by the quest.
        #expect(chain.notes.filter { $0 == "alias.oninit" }.count == 1)
        #expect(chain.session.world.questInstanceKeys.count == 2)
        #expect(chain.session.world.questAliasInstanceCount == 1)

        let aliases = try chain.runtime.aliasState(of: Chain.questFormID)
        #expect(
            aliases.reference(forAlias: Chain.aliasID)
                == Chain.key(Chain.aliasTargetObjectID)
        )

        // A quest is placed nowhere, so its state is unattributed and drags no
        // cell rebuild behind it. One dirty key, because the running flag and
        // the alias table are two components of the QUST record's own key.
        #expect(chain.session.worldState.unattributedDirtyCount == 1)
        #expect(chain.session.worldState.dirtyCount(in: Chain.cell) == 0)
        #expect(chain.session.worldState.component(
            QuestAliasState.self, for: Chain.questKey
        ) != nil)

        // The page lists the quest by its own FULL text as soon as it runs, and
        // shows nothing under it: no stage is reached and no objective is shown.
        let journal = try chain.journal()
        let entry = try #require(journal.selectedEntry)
        #expect(entry.title == Chain.questTitle)
        #expect(entry.kind == .mainQuest)
        #expect(entry.stage == nil)
        #expect(entry.objectives.isEmpty)
        #expect(entry.logEntries.isEmpty)
    }

    /// Step 2 — the lever's cell attaches, which is what binds its `GateQuest`
    /// property to the live quest instance. Binding it is the whole reason the
    /// quest is brought up first.
    private static func attachTheLeversCell(_ chain: Chain) {
        chain.attachCell()

        let world = chain.session.world
        let leverHandle = world.instancesByKey[PapyrusInstanceKey(
            reference: Chain.key(Chain.leverObjectID), scriptName: Chain.leverScript
        )]
        #expect(leverHandle != nil)
        #expect(world.bindingSkips.total == 0, "the lever's quest property did not bind")
        guard
            let leverHandle,
            let instance = world.runtime.instance(for: leverHandle)
        else {
            Issue.record("the lever has no live instance")
            return
        }
        let bound = instance.value(named: "::GateQuest_var", declaredBy: Chain.leverScript)
        #expect(bound == .object(world.objectHandle(for: Chain.questKey)))
    }

    /// Step 3 — the player looks at the lever and presses the use key. The
    /// raycast, the interaction target, the `InteractionEvent` and the
    /// multicast fan-out are all real from there.
    private static func pullTheLever(_ chain: Chain) throws {
        let before = chain.notes.count
        chain.pressUseKey()

        // The trace, in order: the lever's own event body ran, and the stage
        // fragment ran after it on a later tick.
        #expect(Array(chain.notes.dropFirst(before)) == ["fragment.10"])
        #expect(chain.recorder.seen.count == 1)
        guard case let .object(handle) = chain.recorder.seen.first else {
            Issue.record("akActionRef did not arrive as an object")
            return
        }
        #expect(chain.session.world.referenceKey(for: handle) == ReferenceKey.player)

        // The quest-state delta the `Quest.SetStage` native wrote, and the
        // objective the fragment displayed on top of it.
        let state = try chain.state
        #expect(state.stagesReached == [Chain.leverStage])
        #expect(state.stageValue == Chain.leverStage)
        #expect(state.objective(Chain.objectiveIndex).isDisplayed)
        #expect(chain.session.world.questFragmentsQueued == 1)

        // The activation itself is the one write the cell owns; everything the
        // quest wrote stays unattributed.
        #expect(chain.session.worldState.dirtyCount(in: Chain.cell) == 1)
        let activation = try #require(
            chain.session.worldState.journalEntries.last { $0.kind == .activation }
        )
        #expect(activation.key == Chain.key(Chain.leverObjectID))
        #expect(activation.cell == Chain.cell)
        // The quest write came after it, and belongs to no cell.
        #expect(chain.session.worldState.journalEntries.last?.kind == .quest)

        // Nothing in the chain reached for a native OpenSky has not written.
        #expect(chain.session.world.runtime.tally.unimplementedNativeTotal == 0)
        #expect(chain.session.world.runtime.tally.faultTotal == 0)

        // The page has grown by exactly what the stage produced: the reached
        // stage's journal paragraph and the displayed objective.
        let entry = try #require(chain.journal().selectedEntry)
        #expect(entry.stage == Chain.leverStage)
        #expect(entry.logEntries == [Chain.firstJournalText])
        #expect(entry.objectives.map(\.text) == [Chain.objectiveText])
        #expect(entry.objectives.map(\.state) == [.displayed])
    }

    /// Step 4 — the quest is walked to its last stage, its objective is
    /// completed and the quest is flagged complete. Setting a second stage adds
    /// a paragraph rather than replacing one: the journal is a running account.
    private static func finishTheQuest(_ chain: Chain) throws {
        let runtime = try chain.runtime
        try runtime.setStage(Chain.finalStage, on: Chain.questFormID)
        try runtime.setObjectiveCompleted(Chain.objectiveIndex, on: Chain.questFormID)
        try runtime.completeQuest(Chain.questFormID)

        let state = try chain.state
        #expect(state.stagesReached == [Chain.leverStage, Chain.finalStage])
        #expect(state.isCompleted)
        // `CompleteQuest` flags completion and nothing else, so the quest is
        // still running and still on the active page.
        #expect(state.isRunning)

        let entry = try #require(chain.journal().selectedEntry)
        #expect(entry.logEntries == [Chain.firstJournalText, Chain.secondJournalText])
        #expect(entry.objectives.map(\.state) == [.completed])
        #expect(entry.isCompleted)
    }

    /// Steps 5 and 6 — save and load. A brand-new store and a brand-new Papyrus
    /// session restored from the file are in the identical end state, allocator
    /// position included, and the page they build is the same page.
    private static func resumeFromASave(_ chain: Chain) throws {
        let file = try roundTrip(chain)
        let fresh = M13AcceptanceRestore(quest: chain.quest)
        fresh.session.worldState.restore(from: file.snapshot)
        // Same order the app's load path uses: quest instances first, so the
        // restored script variables have somewhere to land.
        fresh.session.bridge.attachRunningQuestScripts()
        fresh.session.world.restore(instanceStates: file.scripts)

        #expect(fresh.session.worldState.snapshot() == chain.session.worldState.snapshot())
        #expect(try fresh.state == chain.state)
        #expect(try fresh.state.stageValue == Chain.finalStage)
        #expect(fresh.session.world.skips.counts[.unknownSaveScript] == nil)

        // The journal the restored session builds is the one the saved session
        // showed, text and objective states included.
        let restored = try fresh.journal()
        #expect(try restored == chain.journal())

        // Nothing re-runs on load: the `OnInit`-fired marks came back with the
        // save, so a fresh drain dispatches nothing.
        PapyrusWorldFixture.drain(fresh.session.world)
        #expect(fresh.session.dispatch.notes.isEmpty)
    }

    // MARK: - Refusals

    /// The quest layer's refusals are ordinary outcomes that write nothing, so
    /// a script bug cannot leave a quest half-advanced.
    @Test("a refused quest mutation leaves the world exactly as it was")
    func refusedMutationsWriteNothing() throws {
        let chain = try Chain()
        try chain.startQuest()
        let runtime = try chain.runtime
        let before = chain.session.worldState.snapshot()

        #expect(throws: QuestError.self) {
            try runtime.setStage(999, on: Chain.questFormID)
        }
        #expect(throws: QuestError.self) {
            try runtime.setObjectiveDisplayed(999, on: Chain.questFormID)
        }
        #expect(throws: QuestError.self) {
            try runtime.setStage(Chain.leverStage, on: FormID(0xDEAD))
        }
        #expect(chain.session.worldState.snapshot() == before)
    }

    /// A stopped quest keeps what it reached and loses its aliases and its
    /// scripts, and it leaves the journal's active page because it is no longer
    /// running.
    @Test("stopping the quest retires its scripts and clears its aliases")
    func stoppingRetiresTheScriptsAndClearsTheAliases() throws {
        let chain = try Chain()
        try chain.startQuest()
        chain.attachCell()
        chain.pressUseKey()

        try chain.session.bridge.stopQuest(for: Chain.questKey)
        let state = try chain.state
        #expect(!state.isRunning)
        #expect(state.stagesReached == [Chain.leverStage])
        #expect(try chain.runtime.aliasState(of: Chain.questFormID).isEmpty)
        #expect(chain.session.world.questInstanceKeys.isEmpty)
        #expect(chain.session.world.questAliasInstanceCount == 0)
        #expect(try JournalMenuModel.build(runtime: chain.runtime, strings: nil).isEmpty)
    }

    // MARK: - Helpers

    /// Writes the session to a real save slot in a temporary directory —
    /// world state and script instances together — and reads it back.
    private static func roundTrip(_ chain: Chain) throws -> OpenSkySaveFile {
        let snapshot = chain.session.worldState.snapshot()
        let directory = URL.temporaryDirectory
            .appending(path: "opensky-m13-\(UInt64(snapshot.sequence))-tests")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let saves = OpenSkySaveStore(directory: directory)
        try saves.save(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            scripts: chain.session.world.instanceStates(),
            toSlot: slot
        )
        return try saves.load(
            slot: slot, verifyingAgainst: OpenSkySaveFixture.fingerprint
        )
    }
}
