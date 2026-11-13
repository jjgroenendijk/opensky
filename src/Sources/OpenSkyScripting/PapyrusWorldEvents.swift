// Fixed-step tick and event dispatch for `PapyrusWorldRuntime`: one FIFO in
// global order, a used-up slice holding its instance, and a budget per tick.

import Foundation
import OpenSkyFormatsCore
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusWorldRuntime.ScriptEvents {
    /// Runs one fixed step: resumes due latent calls, then drains events up to
    /// the budget. It ignores `isPaused`, so agent control can step a paused VM.
    /// All scripts share `budget.instructions`; once it is spent, a new event
    /// yields before its first instruction and waits its turn in the scheduler.
    @discardableResult
    public func stepFixed(gameClock: GameClock? = nil) -> PapyrusTickReport {
        world.runtime.stepInstructionsLeft = max(0, world.budget.instructions)
        let delayedBefore = world.runtime.tally.delayedNativeTotal
        defer {
            world.lastStepInstructions = max(0, world.budget.instructions) - world.runtime
                .stepInstructionsLeft
            world.lastStepDelayedCalls = world.runtime.tally.delayedNativeTotal - delayedBefore
            world.runtime.stepInstructionsLeft = .max
        }
        _ = world.scheduler.tick(gameClock: gameClock)
        let resumes = world.suspensionTracker.drainStep()
        world.timers.advanceUpdateTimers(gameClock: gameClock)
        var dispatched = 0
        var faulted = resumes.faulted
        drainQueue(dispatched: &dispatched, faulted: &faulted)
        world.questRuns.answerLatentQuestWaits()
        world.questRuns.retireShutDownQuests()
        world.lifecycle.retireDrainedInstances()
        let report = PapyrusTickReport(
            steps: 1,
            dispatched: dispatched,
            queued: world.eventQueue.count,
            resumed: resumes.resumed,
            faulted: faulted
        )
        world.retainTickReport(report)
        return report
    }

    /// Runs whole fixed steps from a wall delta, at most `maximumStepsPerAdvance`.
    /// A zero delta (menu mode) runs nothing. While `isPaused` it also stores no
    /// time, so unpausing never runs catch-up steps.
    @discardableResult
    public func advance(delta: Float, gameClock: GameClock? = nil) -> PapyrusTickReport {
        var report = PapyrusTickReport(
            steps: 0, dispatched: 0, queued: world.eventQueue.count,
            resumed: 0, faulted: 0
        )
        guard !world.isPaused else {
            return .zero
        }
        guard delta > 0 else {
            return report
        }
        world.accumulatorSeconds += Double(delta)
        while
            world.accumulatorSeconds >= world.fixedStepSeconds,
            report.steps < PapyrusWorldRuntime.maximumStepsPerAdvance
        {
            world.accumulatorSeconds -= world.fixedStepSeconds
            report = report.adding(stepFixed(gameClock: gameClock))
        }
        // After a capped hitch, keep at most one more burst of debt so a
        // multi-second stall cannot spiral into minutes of catch-up.
        world.accumulatorSeconds = min(
            world.accumulatorSeconds,
            world.fixedStepSeconds * Double(PapyrusWorldRuntime.maximumStepsPerAdvance)
        )
        // A frame too short to complete a step leaves the previous frame's
        // sample in place; the alternative reports zeros for most frames at a
        // render rate above the fixed step.
        if report.steps > 0 {
            world.retainTickReport(report)
        }
        return report
    }

    private func drainQueue(dispatched: inout Int, faulted: inout Int) {
        world.drainCursor = 0
        defer { world.drainCursor = nil }
        var retained: [PapyrusScriptEvent] = []
        while
            let index = world.drainCursor, index < world.eventQueue.count,
            dispatched < world.budget.events
        {
            let event = world.eventQueue[index]
            world.drainCursor = index + 1
            guard !world.busyInstances.contains(event.target) else {
                retained.append(event)
                continue
            }
            dispatched += 1
            // Recorded for every event the drain consumed, including the
            // counted no-ops below, so the ring matches `dispatched`.
            world.recordDispatchedEvent(event)
            guard let outcome = dispatch(event) else {
                continue
            }
            if settle(outcome, target: event.target) {
                faulted += 1
            }
        }
        // Skipped busy-instance events keep their order ahead of the
        // untouched tail; both were behind the dispatched prefix.
        world.eventQueue = retained + Array(world.eventQueue.dropFirst(world.drainCursor ?? 0))
    }

    /// Hands `outcome` to the scheduler and tracks a suspended call of `target`.
    /// Returns true for a fault.
    func settle(_ outcome: PapyrusRunOutcome, target: PapyrusInstanceKey) -> Bool {
        if case let .suspended(call) = outcome {
            world.suspensionTracker.begin(call, instance: target)
        }
        world.scheduler.schedule(outcome)
        if case .faulted = outcome {
            return true
        }
        return false
    }

    /// Delivers one event. Returns nil for a counted no-op: a retired
    /// target, a repeated `OnInit`, or a function the script chain does not
    /// define — none of which is a fault.
    private func dispatch(_ event: PapyrusScriptEvent) -> PapyrusRunOutcome? {
        guard
            let handle = world.instancesByKey[event.target],
            let instance = world.runtime.instance(for: handle)
        else {
            world.skips.note(.retiredEventTarget)
            return nil
        }
        if PapyrusRuntime.matches(event.functionName, PapyrusEngineEvents.onInit) {
            guard !world.firedOnInit.contains(event.target) else {
                return nil
            }
            world.firedOnInit.insert(event.target)
            world.pendingOnInit.remove(event.target)
        }
        guard definesFunction(event.functionName, instance: instance) else {
            world.skips.note(.undefinedEventFunction)
            return nil
        }
        // An `Activate` native called from this handler queues its own events
        // one level deeper, which is what bounds an activation ping-pong.
        return world.withActivationDepth(event.activationDepth) {
            world.runtime.invoke(
                event.functionName, on: handle, arguments: event.arguments
            )
        }
    }

    /// Whether the script chain of `key`'s instance declares `name`.
    func definesFunction(_ name: String, key: PapyrusInstanceKey) -> Bool {
        guard
            let handle = world.instancesByKey[key],
            let instance = world.runtime.instance(for: handle)
        else { return false }
        return definesFunction(name, instance: instance)
    }

    private func definesFunction(
        _ name: String,
        instance: PapyrusInstance
    ) -> Bool {
        let interpreter = PapyrusRuntime.Interpreter(runtime: world.runtime)
        // `attempt` flattens the throwing call's own optional, so a nil here is
        // either a resolution failure or a name the chain does not declare.
        return attempt { try interpreter.resolveMethod(name, instance: instance) } != nil
    }
}
