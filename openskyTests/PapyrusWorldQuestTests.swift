// Quest script instances and stage fragments (issue #322, roadmap item 13.3):
// the lifecycle half. `PapyrusNativeQuestTests` covers the natives themselves.
//
// Fixtures are synthetic, built in code by `PapyrusQuestFixture` — never
// extracted game files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusWorldQuestTests {
    /// A start-game-enabled quest gets its scripts at wire-up: the VMAD script
    /// and the generated fragment script, both keyed by the quest's own
    /// `ReferenceKey`, both persistent, and neither owned by a cell.
    @Test func startGameEnabledQuestInstantiatesItsScripts() throws {
        let session = try PapyrusQuestFixture.session(quest: PapyrusQuestFixture.quest())
        let world = session.world

        #expect(world.questCount == 1)
        #expect(world.questInstanceKeys.count == 2)
        #expect(world.instancesByKey[
            PapyrusQuestFixture.instanceKey(PapyrusQuestFixture.questScript)
        ] != nil)
        #expect(world.instancesByKey[
            PapyrusQuestFixture.instanceKey(PapyrusQuestFixture.fragmentScript)
        ] != nil)
        #expect(world.attachedByCell.isEmpty)
        #expect(world.persistentKeys == world.questInstanceKeys)
    }

    /// A quest that is not running gets no instances, and starting it is what
    /// creates them. `OnInit` fires exactly once however many ticks run.
    @Test func startCreatesInstancesAndFiresOnInitOnce() throws {
        let quest = try PapyrusQuestFixture.quest(startGameEnabled: false)
        let session = PapyrusQuestFixture.session(quest: quest)
        #expect(session.world.questInstanceKeys.isEmpty)

        try session.bridge.startQuest(for: PapyrusQuestFixture.questKey)
        PapyrusWorldFixture.drain(session.world)
        #expect(session.dispatch.notes.filter { $0 == "quest.oninit" }.count == 1)

        // Starting a running quest is a no-op: no second instance, no second
        // `OnInit`.
        try session.bridge.startQuest(for: PapyrusQuestFixture.questKey)
        PapyrusWorldFixture.drain(session.world)
        #expect(session.world.questInstanceKeys.count == 2)
        #expect(session.dispatch.notes.filter { $0 == "quest.oninit" }.count == 1)
    }

    /// Setting a stage runs that stage's fragment exactly once, and a repeat of
    /// the same stage runs nothing: the stage is already in the reached set.
    @Test func settingAStageRunsItsFragmentOnce() throws {
        let session = try PapyrusQuestFixture.session(quest: PapyrusQuestFixture.quest())
        PapyrusWorldFixture.drain(session.world)

        try session.bridge.setQuestStage(
            PapyrusQuestFixture.fragmentStage, for: PapyrusQuestFixture.questKey
        )
        PapyrusWorldFixture.drain(session.world)
        #expect(session.dispatch.notes.filter { $0 == "fragment.10" }.count == 1)

        try session.bridge.setQuestStage(
            PapyrusQuestFixture.fragmentStage, for: PapyrusQuestFixture.questKey
        )
        PapyrusWorldFixture.drain(session.world)
        #expect(session.dispatch.notes.filter { $0 == "fragment.10" }.count == 1)
        #expect(session.world.questFragmentsQueued == 1)
    }

    /// A stage with several fragments queues them in fragment-table order, and
    /// the queue keeps that order through dispatch.
    @Test func fragmentsRunInTableOrder() throws {
        let quest = try PapyrusQuestFixture.quest(fragments: [
            QuestFixture.Fragment(
                stage: PapyrusQuestFixture.fragmentStage,
                script: PapyrusQuestFixture.fragmentScript,
                function: "Fragment_0"
            ),
            QuestFixture.Fragment(
                stage: PapyrusQuestFixture.fragmentStage,
                logEntry: 1,
                script: PapyrusQuestFixture.fragmentScript,
                function: "Fragment_1"
            )
        ])
        let session = PapyrusQuestFixture.session(
            quest: quest,
            objects: PapyrusQuestFixture.objects(fragmentFunctions: [
                ("Fragment_0", PapyrusWorldFixture.probeBody(note: "fragment.0")),
                ("Fragment_1", PapyrusWorldFixture.probeBody(note: "fragment.1"))
            ])
        )
        PapyrusWorldFixture.drain(session.world)

        try session.bridge.setQuestStage(
            PapyrusQuestFixture.fragmentStage, for: PapyrusQuestFixture.questKey
        )
        PapyrusWorldFixture.drain(session.world)
        // The `OnInit` notes from the attach come first; the fragments are the tail.
        #expect(Array(session.dispatch.notes.suffix(2)) == ["fragment.0", "fragment.1"])
    }

    /// A fragment naming a script the quest holds no instance of is counted,
    /// never a fault: the quest keeps running with the stage set.
    @Test func fragmentWithNoInstanceIsCountedNotFaulted() throws {
        let quest = try PapyrusQuestFixture.quest(fragments: [
            QuestFixture.Fragment(
                stage: PapyrusQuestFixture.fragmentStage,
                script: "QF_ScriptThatIsNotInTheLibrary",
                function: "Fragment_0"
            )
        ])
        let session = PapyrusQuestFixture.session(quest: quest)
        PapyrusWorldFixture.drain(session.world)

        try session.bridge.setQuestStage(
            PapyrusQuestFixture.fragmentStage, for: PapyrusQuestFixture.questKey
        )
        PapyrusWorldFixture.drain(session.world)
        #expect(session.world.skips.counts[.missingQuestFragmentInstance] == 1)
        #expect(session.world.runtime.tally.faultTotal == 0)
        #expect(try PapyrusQuestFixture.state(session).isStageDone(
            PapyrusQuestFixture.fragmentStage
        ))
    }

    /// `Stop` retires the quest's instances, their queued events and their
    /// `OnInit`-fired marks, so a later `Start` runs `OnInit` on fresh ones.
    @Test func stopRetiresTheInstancesAndStartBringsThemBack() throws {
        let session = try PapyrusQuestFixture.session(quest: PapyrusQuestFixture.quest())
        PapyrusWorldFixture.drain(session.world)
        #expect(session.dispatch.notes.filter { $0 == "quest.oninit" }.count == 1)

        try session.bridge.stopQuest(for: PapyrusQuestFixture.questKey)
        #expect(session.world.questInstanceKeys.isEmpty)
        #expect(session.world.instancesByKey.isEmpty)
        #expect(session.world.persistentKeys.isEmpty)

        try session.bridge.startQuest(for: PapyrusQuestFixture.questKey)
        PapyrusWorldFixture.drain(session.world)
        #expect(session.world.questInstanceKeys.count == 2)
        #expect(session.dispatch.notes.filter { $0 == "quest.oninit" }.count == 2)
    }

    /// A shut-down stage stops the quest and deliberately keeps its instances,
    /// so the fragment that stage queued still runs. Only `Stop` retires them.
    @Test func shutDownStageKeepsInstancesSoItsFragmentStillRuns() throws {
        let quest = try PapyrusQuestFixture.quest(fragments: [
            QuestFixture.Fragment(
                stage: PapyrusQuestFixture.shutDownStage,
                script: PapyrusQuestFixture.fragmentScript,
                function: "Fragment_0"
            )
        ])
        let session = PapyrusQuestFixture.session(
            quest: quest,
            objects: PapyrusQuestFixture.objects(fragmentFunctions: [
                ("Fragment_0", PapyrusWorldFixture.probeBody(note: "fragment.shutdown"))
            ])
        )
        PapyrusWorldFixture.drain(session.world)

        try session.bridge.setQuestStage(
            PapyrusQuestFixture.shutDownStage, for: PapyrusQuestFixture.questKey
        )
        PapyrusWorldFixture.drain(session.world)
        #expect(try !PapyrusQuestFixture.state(session).isRunning)
        #expect(Array(session.dispatch.notes.suffix(1)) == ["fragment.shutdown"])
    }

    /// A quest is not attached to any cell, so no cell detach can reach it —
    /// including the world-space transition that retires everything else.
    @Test func questInstancesSurviveCellDetach() throws {
        let entry = try PapyrusWorldFixture.referenceEntry(
            objectID: 0x0000_0AAA,
            scripts: [VMADFixture.Script("Lever", properties: [])]
        )
        let session = try PapyrusQuestFixture.session(
            quest: PapyrusQuestFixture.quest(),
            objects: PapyrusQuestFixture.objects([
                PapyrusWorldFixture.fullEventScript("Lever")
            ]),
            entries: [entry]
        )
        PapyrusWorldFixture.drain(session.world)
        #expect(session.world.instancesByKey.count == 3)

        session.world.detach(cell: PapyrusWorldFixture.cell)
        #expect(session.world.instancesByKey.count == 2)
        #expect(session.world.questInstanceKeys.count == 2)
    }

    /// The M13 gameplay loop end to end: a world event fires a reference
    /// script, the script sets a stage on its quest property, and the fragment
    /// for that stage runs and mutates world state.
    @Test func aWorldEventDrivesTheQuestThroughItsFragment() throws {
        let session = try PapyrusQuestFixture.session(quest: PapyrusQuestFixture.quest())
        PapyrusWorldFixture.drain(session.world)

        // The event the engine would deliver; `OnProbeAdvance` calls
        // `self.SetStage(10)` through the synthetic `Quest` parent class.
        session.world.enqueue(PapyrusScriptEvent(
            target: PapyrusQuestFixture.instanceKey(PapyrusQuestFixture.questScript),
            functionName: "OnProbeAdvance",
            arguments: []
        ))
        PapyrusWorldFixture.drain(session.world)

        #expect(Array(session.dispatch.notes.suffix(1)) == ["fragment.10"])
        let state = try PapyrusQuestFixture.state(session)
        #expect(state.isStageDone(PapyrusQuestFixture.fragmentStage))
        #expect(state.stageValue == PapyrusQuestFixture.fragmentStage)
        #expect(session.world.runtime.tally.unimplementedNativeTotal == 0)
    }

    /// A save taken mid-quest restores into a fresh runtime and store: the same
    /// instances, the same variables, the same `OnInit`-fired marks and the
    /// same quest state, with `instanceStates()` equal on both sides.
    @Test func aMidQuestSaveRestoresIntoAFreshRuntime() throws {
        let quest = try PapyrusQuestFixture.quest()
        let source = PapyrusQuestFixture.session(quest: quest)
        PapyrusWorldFixture.drain(source.world)
        try source.bridge.setQuestStage(
            PapyrusQuestFixture.fragmentStage, for: PapyrusQuestFixture.questKey
        )
        PapyrusWorldFixture.drain(source.world)

        let file = try OpenSkySaveDecoder.decode(OpenSkySaveEncoder.encode(
            snapshot: source.worldState.snapshot(),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            scripts: source.world.instanceStates()
        ))
        let fresh = PapyrusQuestFixture.session(quest: quest, attachQuests: false)
        fresh.worldState.restore(from: file.snapshot)
        // Same order the app's load path uses: quest instances first, so the
        // restored variables have somewhere to land.
        fresh.bridge.attachRunningQuestScripts()
        fresh.world.restore(instanceStates: file.scripts)

        #expect(fresh.world.instanceStates() == source.world.instanceStates())
        #expect(try PapyrusQuestFixture.state(fresh) == PapyrusQuestFixture.state(source))
        #expect(fresh.world.skips.counts[.unknownSaveScript] == nil)

        // Nothing re-runs on load: the fired set came back with the save.
        PapyrusWorldFixture.drain(fresh.world)
        #expect(fresh.dispatch.notes.isEmpty)
    }
}
