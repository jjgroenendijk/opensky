// Fixed-step tick and event dispatch for `PapyrusWorldRuntime`.
//
// Semantics (issue #171): one main-actor FIFO with global order preserved;
// per-instance serial delivery, so events for an instance suspended in a
// latent call stay queued in order while other instances proceed; a
// budget-bounded drain per tick with carry-over to the next frame.

import Foundation

extension PapyrusWorldRuntime {
    /// Advances exactly one fixed step: resumes due latent calls, then drains
    /// queued events up to the budget. Deterministic; offscreen renders and
    /// tests drive this directly.
    ///
    /// Runs whether or not `isPaused` is set: this is the primitive the
    /// sidebar's step-one-tick control drives, and stepping a paused VM is
    /// the whole point of pausing it.
    @discardableResult
    func stepFixed(gameClock: GameClock? = nil) -> PapyrusTickReport {
        _ = scheduler.tick(gameClock: gameClock)
        let resumes = suspensionTracker.drainStep()
        for key in resumes.settledInstances {
            busyInstances.remove(key)
        }
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

    /// Accumulates a wall delta and runs whole fixed steps only, capped at
    /// `maximumStepsPerAdvance` per call; the remainder carries in the
    /// accumulator. A zero delta — the paused case per `FrameSimClock`'s
    /// contract — advances zero steps, dispatches nothing, and resumes
    /// nothing, but is safe to call every frame. The engine's own pause —
    /// menu mode — arrives that way, as delta 0.
    ///
    /// `isPaused` is the VM's separate, sidebar-driven pause (issue #278) and
    /// is handled here rather than by the caller: a paused call returns the
    /// same zero report and, crucially, accumulates nothing, so however long
    /// the VM stays paused, unpausing never runs a burst of catch-up steps.
    @discardableResult
    func advance(delta: Float, gameClock: GameClock? = nil) -> PapyrusTickReport {
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
        var index = 0
        var retained: [PapyrusScriptEvent] = []
        while
            index < eventQueue.count,
            dispatched < budget.events,
            runtime.tally.instructionsExecuted - instructionFloor
            < budget.instructions
        {
            let event = eventQueue[index]
            index += 1
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
            if case let .suspended(call) = outcome {
                busyInstances.insert(event.target)
                suspensionTracker.begin(id: call.id, instance: event.target)
            }
            if case .faulted = outcome {
                faulted += 1
            }
            scheduler.schedule(outcome)
        }
        // Skipped busy-instance events keep their order ahead of the
        // untouched tail; both were behind the dispatched prefix.
        eventQueue = retained + Array(eventQueue[index...])
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
