// FIFO event queue semantics for `PapyrusWorldRuntime` (issue #171):
// budget-bounded drain with carry-over, global order, per-instance serial
// delivery across a latent suspension, and the fixed-step latent wake.

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusWorldEventQueueTests {
    @Test("events beyond the budget carry over, in global FIFO order")
    func budgetCarryOver() throws {
        let probe = PapyrusWorldProbeDispatch()
        let world = try attachedWorld(probe: probe)
        world.budget = PapyrusTickBudget(events: 2, instructions: 100_000)
        for turn in 0 ..< 5 {
            let target = turn.isMultiple(of: 2) ? aKey : bKey
            world.enqueue(PapyrusScriptEvent(
                target: target, functionName: "OnLoad", arguments: []
            ))
        }

        let first = world.stepFixed()
        #expect(first.dispatched == 2)
        #expect(first.queued == 3)
        let second = world.stepFixed()
        #expect(second.dispatched == 2)
        #expect(second.queued == 1)
        let third = world.stepFixed()
        #expect(third.dispatched == 1)
        #expect(third.queued == 0)
        #expect(probe.notes == [
            "a.onload", "b.onload", "a.onload", "b.onload", "a.onload"
        ])
    }

    @Test("same-instance events never interleave across a latent suspension")
    func perInstanceSerialDelivery() throws {
        let probe = PapyrusWorldProbeDispatch()
        let waiter = PapyrusWorldFixture.eventScript("WaiterScript", events: [
            ("OnLoad", PapyrusWorldFixture.probeBody(note: "waiter.done", waitSeconds: 2)),
            ("OnCellAttach", PapyrusWorldFixture.probeBody(note: "waiter.attach"))
        ])
        let bystander = PapyrusWorldFixture.eventScript("BystanderScript", events: [
            ("OnLoad", PapyrusWorldFixture.probeBody(note: "bystander.onload"))
        ])
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [waiter, bystander],
            nativeDispatch: probe,
            fixedStepSeconds: 1
        )
        let references = try PapyrusWorldFixture.index([
            PapyrusWorldFixture.referenceEntry(
                objectID: 1, scripts: [.init("WaiterScript", properties: [])]
            ),
            PapyrusWorldFixture.referenceEntry(
                objectID: 2, scripts: [.init("BystanderScript", properties: [])]
            )
        ])
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: references,
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        let waiterKey = PapyrusWorldFixture.key(objectID: 1, script: "WaiterScript")
        world.eventQueue = [
            PapyrusScriptEvent(target: waiterKey, functionName: "OnLoad", arguments: []),
            PapyrusScriptEvent(target: waiterKey, functionName: "OnCellAttach", arguments: []),
            PapyrusScriptEvent(
                target: PapyrusWorldFixture.key(objectID: 2, script: "BystanderScript"),
                functionName: "OnLoad",
                arguments: []
            )
        ]

        // Step 1: the waiter's OnLoad suspends in Utility.Wait(2); its
        // OnCellAttach must stay queued while the bystander proceeds.
        let first = world.stepFixed()
        #expect(first.dispatched == 2)
        #expect(first.queued == 1)
        #expect(probe.notes == ["bystander.onload"])

        let second = world.stepFixed()
        #expect(second.resumed == 0)
        #expect(second.dispatched == 0)
        #expect(probe.notes == ["bystander.onload"])

        // Step 3: two 1 s steps have elapsed since the suspension, so the
        // wait resumes, the handler finishes, and only then does the queued
        // OnCellAttach for the same instance run.
        let third = world.stepFixed()
        #expect(third.resumed == 1)
        #expect(third.dispatched == 1)
        #expect(probe.notes == ["bystander.onload", "waiter.done", "waiter.attach"])
    }

    @Test("Utility.Wait(1.0) resumes after exactly 30 fixed 1/30 steps")
    func waitResumesAfterExactlyThirtySteps() throws {
        let probe = PapyrusWorldProbeDispatch()
        let waiter = PapyrusWorldFixture.eventScript("WaiterScript", events: [
            ("OnLoad", PapyrusWorldFixture.probeBody(note: "waiter.done", waitSeconds: 1.0))
        ])
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [waiter], nativeDispatch: probe
        )
        let references = try PapyrusWorldFixture.index([
            PapyrusWorldFixture.referenceEntry(
                objectID: 1, scripts: [.init("WaiterScript", properties: [])]
            )
        ])
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: references,
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        world.eventQueue = [PapyrusScriptEvent(
            target: PapyrusWorldFixture.key(objectID: 1, script: "WaiterScript"),
            functionName: "OnLoad",
            arguments: []
        )]
        #expect(world.stepFixed().dispatched == 1) // suspends in the wait

        for step in 1 ... 29 {
            let report = world.stepFixed()
            #expect(report.resumed == 0, "resumed early at step \(step)")
        }
        #expect(probe.notes.isEmpty)
        let thirtieth = world.stepFixed()
        #expect(thirtieth.resumed == 1)
        #expect(probe.notes == ["waiter.done"])
    }

    @Test("a zero delta advances nothing but is safe every frame")
    func zeroDeltaIsInert() throws {
        let probe = PapyrusWorldProbeDispatch()
        let world = try attachedWorld(probe: probe)
        world.enqueue(PapyrusScriptEvent(
            target: aKey, functionName: "OnLoad", arguments: []
        ))
        for _ in 0 ..< 3 {
            let report = world.advance(delta: 0)
            #expect(report.steps == 0)
            #expect(report.dispatched == 0)
            #expect(report.resumed == 0)
            #expect(report.queued == 1)
        }
        #expect(world.scheduler.tickCount == 0)
        #expect(probe.notes.isEmpty)
    }

    @Test("advance accumulates partial deltas and caps a hitch at four steps")
    func advanceAccumulatesAndCaps() throws {
        let world = try attachedWorld(probe: PapyrusWorldProbeDispatch())
        #expect(world.advance(delta: 1.0 / 60.0).steps == 0)
        #expect(world.advance(delta: 1.0 / 60.0).steps == 1)
        #expect(world.advance(delta: 10).steps == 4)
    }

    @Test("an event function the script does not define is a counted no-op")
    func undefinedFunctionIsANoOp() throws {
        let world = try attachedWorld(probe: PapyrusWorldProbeDispatch())
        world.enqueue(PapyrusScriptEvent(
            target: aKey, functionName: "OnNothingDefined", arguments: []
        ))
        let report = world.stepFixed()
        #expect(report.dispatched == 1)
        #expect(report.faulted == 0)
        #expect(world.skips.counts[.undefinedEventFunction] == 1)
    }

    private var aKey: PapyrusInstanceKey {
        PapyrusWorldFixture.key(objectID: 1, script: "AScript")
    }

    private var bKey: PapyrusInstanceKey {
        PapyrusWorldFixture.key(objectID: 2, script: "BScript")
    }

    /// World with two loaded instances (references 1 and 2) whose `OnLoad`
    /// records "a.onload" / "b.onload", with the attach events drained.
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
        // instances with no pending events and no notes recorded.
        world.eventQueue.removeAll()
        return world
    }
}
