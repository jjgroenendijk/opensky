// Fixed-step tick and event dispatch for `PapyrusWorldRuntime`: one FIFO in
// global order, a used-up slice holding its instance, and a budget per tick.

import Foundation
import OpenSkyFormatsCore
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusWorldRuntime {
    /// Runs one fixed step: resumes due latent calls, then drains events up to
    /// the budget. It ignores `isPaused`, so the sidebar can step a paused VM.
    @discardableResult
    public func stepFixed(gameClock: GameClock? = nil) -> PapyrusTickReport {
        _ = scheduler.tick(gameClock: gameClock)
        let resumes = suspensionTracker.drainStep()
        advanceUpdateTimers(gameClock: gameClock)
        var dispatched = 0
        var faulted = resumes.faulted
        drainQueue(dispatched: &dispatched, faulted: &faulted)
        let report = PapyrusTickReport(
            steps: 1,
            dispatched: dispatched,
            queued: eventQueue.count,
            resumed: resumes.resumed,
            faulted: faulted
        )
        retainTickReport(report)
        return report
    }

    /// Runs whole fixed steps from a wall delta, at most `maximumStepsPerAdvance`.
    /// A zero delta (menu mode) runs nothing. While `isPaused` it also stores no
    /// time, so unpausing never runs catch-up steps.
    @discardableResult
    public func advance(delta: Float, gameClock: GameClock? = nil) -> PapyrusTickReport {
        var report = PapyrusTickReport(
            steps: 0, dispatched: 0, queued: eventQueue.count,
            resumed: 0, faulted: 0
        )
        guard !isPaused else {
            return .zero
        }
        guard delta > 0 else {
            return report
        }
        accumulatorSeconds += Double(delta)
        while
            accumulatorSeconds >= fixedStepSeconds,
            report.steps < Self.maximumStepsPerAdvance
        {
            accumulatorSeconds -= fixedStepSeconds
            report = report.adding(stepFixed(gameClock: gameClock))
        }
        // After a capped hitch, keep at most one more burst of debt so a
        // multi-second stall cannot spiral into minutes of catch-up.
        accumulatorSeconds = min(
            accumulatorSeconds,
            fixedStepSeconds * Double(Self.maximumStepsPerAdvance)
        )
        // A frame too short to complete a step leaves the previous frame's
        // sample in place; the alternative reports zeros for most frames at a
        // render rate above the fixed step.
        if report.steps > 0 {
            retainTickReport(report)
        }
        return report
    }

    private func drainQueue(dispatched: inout Int, faulted: inout Int) {
        let instructionFloor = runtime.tally.instructionsExecuted
        drainCursor = 0
        defer { drainCursor = nil }
        var retained: [PapyrusScriptEvent] = []
        while
            let index = drainCursor, index < eventQueue.count,
            dispatched < budget.events,
            runtime.tally.instructionsExecuted - instructionFloor
            < budget.instructions
        {
            let event = eventQueue[index]
            drainCursor = index + 1
            guard !busyInstances.contains(event.target) else {
                retained.append(event)
                continue
            }
            dispatched += 1
            // Recorded for every event the drain consumed, including the
            // counted no-ops below, so the ring matches `dispatched`.
            recordDispatchedEvent(event)
            guard let outcome = dispatch(event) else {
                continue
            }
            if settle(outcome, target: event.target) {
                faulted += 1
            }
        }
        // Skipped busy-instance events keep their order ahead of the
        // untouched tail; both were behind the dispatched prefix.
        eventQueue = retained + Array(eventQueue.dropFirst(drainCursor ?? 0))
    }

    /// Hands `outcome` to the scheduler and tracks a suspended call of `target`.
    /// Returns true for a fault.
    func settle(_ outcome: PapyrusRunOutcome, target: PapyrusInstanceKey) -> Bool {
        if case let .suspended(call) = outcome {
            suspensionTracker.begin(call, instance: target)
        }
        scheduler.schedule(outcome)
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
            let handle = instancesByKey[event.target],
            let instance = runtime.instance(for: handle)
        else {
            skips.note(.retiredEventTarget)
            return nil
        }
        if PapyrusRuntime.matches(event.functionName, Self.onInitEventName) {
            guard !firedOnInit.contains(event.target) else {
                return nil
            }
            firedOnInit.insert(event.target)
            pendingOnInit.remove(event.target)
        }
        guard definesFunction(event.functionName, instance: instance) else {
            skips.note(.undefinedEventFunction)
            return nil
        }
        // An `Activate` native called from this handler queues its own events
        // one level deeper, which is what bounds an activation ping-pong.
        return withActivationDepth(event.activationDepth) {
            runtime.invoke(
                event.functionName, on: handle, arguments: event.arguments
            )
        }
    }

    private func definesFunction(
        _ name: String,
        instance: PapyrusInstance
    ) -> Bool {
        let interpreter = PapyrusInterpreter(runtime: runtime)
        // `try?` flattens the throwing call's own optional, so a nil here is
        // either a resolution failure or a name the chain does not declare.
        return (try? interpreter.resolveMethod(name, instance: instance)) != nil
    }
}
