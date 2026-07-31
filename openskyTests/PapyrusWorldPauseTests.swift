// VM pause, single-stepping, the recent-event ring, and the Scripts snapshot
// the World > Scripts sidebar reads (issue #278). Every fixture is built in
// code by `PapyrusWorldFixture`; no game data is involved.

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusWorldPauseTests {
    @Test("a paused advance runs nothing and accumulates nothing")
    func pausedAdvanceIsInert() throws {
        let probe = PapyrusWorldProbeDispatch()
        let world = try attachedWorld(probe: probe)
        world.enqueue(onLoad())
        world.isPaused = true

        for _ in 0 ..< 5 {
            #expect(world.advance(delta: 1.0) == .zero)
        }
        #expect(world.scheduler.tickCount == 0)
        #expect(probe.notes.isEmpty)
        #expect(world.accumulatorSeconds == 0)

        // Unpausing must not replay the five paused seconds as catch-up: the
        // first frame after it may run at most the one step its own delta
        // pays for.
        world.isPaused = false
        #expect(world.advance(delta: 1.0 / 30.0).steps == 1)
        #expect(probe.notes == ["a.onload"])
    }

    @Test("stepFixed still runs while the VM is paused")
    func stepFixedRunsWhilePaused() throws {
        let probe = PapyrusWorldProbeDispatch()
        let world = try attachedWorld(probe: probe)
        world.isPaused = true
        world.enqueue(onLoad())

        let report = world.stepFixed()
        #expect(report.steps == 1)
        #expect(report.dispatched == 1)
        #expect(probe.notes == ["a.onload"])
        #expect(world.scheduler.tickCount == 1)
    }

    @Test("burst runs the requested ticks and clamps a stray count")
    func burstStepsAreBounded() throws {
        let world = try attachedWorld(probe: PapyrusWorldProbeDispatch())
        world.isPaused = true
        world.burst(ticks: 3)
        #expect(world.scheduler.tickCount == 3)
        world.burst(ticks: -1)
        #expect(world.scheduler.tickCount == 3)
        world.burst(ticks: 10000)
        #expect(world.scheduler.tickCount == 3 + PapyrusWorldRuntime.maximumBurstTicks)
    }

    @Test("the recent-event ring keeps the newest eight and counts the rest")
    func recentEventRingIsBounded() throws {
        let world = try attachedWorld(probe: PapyrusWorldProbeDispatch())
        for _ in 0 ..< 11 {
            world.enqueue(onLoad())
        }
        PapyrusWorldFixture.drain(world)

        #expect(world.recentEvents.count == PapyrusWorldRuntime.recentEventLimit)
        #expect(world.recentEvents.allSatisfy { $0 == "OnLoad -> ascript" })
        #expect(world.droppedRecentEventCount == 3)
    }

    @Test("the ring records the event name of every dispatched event")
    func recentEventNamesFollowDispatch() throws {
        let world = try attachedWorld(probe: PapyrusWorldProbeDispatch())
        world.enqueue(onLoad())
        world.enqueue(PapyrusScriptEvent(
            target: bKey, functionName: "OnActivate", arguments: []
        ))
        PapyrusWorldFixture.drain(world)

        #expect(world.recentEvents == ["OnLoad -> ascript", "OnActivate -> bscript"])
        #expect(world.droppedRecentEventCount == 0)
    }

    @Test("the last tick report survives frames that step nothing")
    func lastTickReportIsRetained() throws {
        let world = try attachedWorld(probe: PapyrusWorldProbeDispatch())
        #expect(world.lastTickReport == .zero)
        world.enqueue(onLoad())

        #expect(world.advance(delta: 1.0 / 30.0).steps == 1)
        #expect(world.lastTickReport.steps == 1)
        #expect(world.lastTickReport.dispatched == 1)

        // A sub-step frame, a zero delta, and a paused frame each advance
        // nothing, so none of them may wipe the sample above.
        _ = world.advance(delta: 1.0 / 120.0)
        _ = world.advance(delta: 0)
        world.isPaused = true
        _ = world.advance(delta: 1.0)
        #expect(world.lastTickReport.dispatched == 1)
    }

    @Test("the scripts snapshot mirrors the runtime's own counters")
    func scriptsSnapshotMirrorsRuntime() throws {
        let world = try attachedWorld(probe: PapyrusWorldProbeDispatch())
        world.isPaused = true
        world.enqueue(onLoad())
        world.stepFixed()

        let snapshot = world.scriptsSnapshot(target: aKey.reference)
        #expect(snapshot.instanceCount == 2)
        #expect(snapshot.targetDescription == aKey.reference.description)
        #expect(snapshot.targetScripts == ["ascript"])
        #expect(snapshot.recentEvents == ["OnLoad -> ascript"])
        #expect(snapshot.pendingEventCount == 0)
        #expect(snapshot.isPaused)
        #expect(snapshot.tickCount == 1)
        #expect(snapshot.budgetEvents == PapyrusTickBudget.standard.events)
        #expect(snapshot.lastTickSteps == 1)
        #expect(snapshot.lastTickDispatched == 1)
        // The probe dispatch answers "Probe.Note" itself, so the one native
        // call the handler makes counts as implemented.
        #expect(snapshot.nativeCallTotal == 1)
        #expect(snapshot.implementedNativeNameCount == 1)
        #expect(snapshot.unimplementedNativeTotal == 0)
        #expect(snapshot.topUnimplementedNatives.isEmpty)
    }

    @Test("an untargeted snapshot names no reference and no scripts")
    func scriptsSnapshotWithoutTarget() throws {
        let world = try attachedWorld(probe: PapyrusWorldProbeDispatch())
        let snapshot = world.scriptsSnapshot()
        #expect(snapshot.targetDescription == nil)
        #expect(snapshot.targetScripts.isEmpty)
        #expect(snapshot.pendingWaitCount == 0)
        #expect(snapshot.pendingTimerCount == 0)
    }

    @Test("the empty snapshot is the all-zero readout")
    func emptySnapshotIsZeroed() {
        let empty = ScriptsSnapshot.empty
        #expect(empty.instanceCount == 0)
        #expect(empty.targetDescription == nil)
        #expect(empty.targetScripts.isEmpty)
        #expect(empty.recentEvents.isEmpty)
        #expect(empty.droppedRecentEventCount == 0)
        #expect(empty.pendingEventCount == 0)
        #expect(!empty.isPaused)
        #expect(empty.pendingWaitCount == 0)
        #expect(empty.pendingTimerCount == 0)
        #expect(empty.tickCount == 0)
        #expect(empty.budgetEvents == 0)
        #expect(empty.budgetInstructions == 0)
        #expect(empty.lastTickSteps == 0)
        #expect(empty.lastTickDispatched == 0)
        #expect(empty.lastTickQueued == 0)
        #expect(empty.lastTickResumed == 0)
        #expect(empty.lastTickFaulted == 0)
        #expect(empty.nativeCallTotal == 0)
        #expect(empty.implementedNativeNameCount == 0)
        #expect(empty.unimplementedNativeTotal == 0)
        #expect(empty.topUnimplementedNatives.isEmpty)
    }

    private var aKey: PapyrusInstanceKey {
        PapyrusWorldFixture.key(objectID: 1, script: "AScript")
    }

    private var bKey: PapyrusInstanceKey {
        PapyrusWorldFixture.key(objectID: 2, script: "BScript")
    }

    private func onLoad() -> PapyrusScriptEvent {
        PapyrusScriptEvent(target: aKey, functionName: "OnLoad", arguments: [])
    }

    /// World with two loaded instances (references 1 and 2) whose `OnLoad`
    /// records "a.onload" / "b.onload", with the attach events drained and
    /// the ring left clean.
    private func attachedWorld(
        probe: PapyrusWorldProbeDispatch
    ) throws -> PapyrusWorldRuntime {
        let aScript = PapyrusWorldFixture.eventScript("AScript", events: [
            ("OnLoad", PapyrusWorldFixture.probeBody(note: "a.onload"))
        ])
        let bScript = PapyrusWorldFixture.eventScript("BScript", events: [
            ("OnLoad", PapyrusWorldFixture.probeBody(note: "b.onload"))
        ])
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [aScript, bScript], nativeDispatch: probe
        )
        let references = try PapyrusWorldFixture.index([
            PapyrusWorldFixture.referenceEntry(
                objectID: 1, scripts: [.init("AScript", properties: [])]
            ),
            PapyrusWorldFixture.referenceEntry(
                objectID: 2, scripts: [.init("BScript", properties: [])]
            )
        ])
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: references,
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        // Attach only enqueues, so discarding the queue leaves two live
        // instances with nothing pending and nothing yet dispatched.
        world.eventQueue.removeAll()
        return world
    }
}
