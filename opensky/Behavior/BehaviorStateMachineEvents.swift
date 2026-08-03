// The event, condition, and reporting half of state-machine evaluation
// (issue #330). Split from `BehaviorStateMachineEvaluation.swift` so neither
// file passes the length limit.
//
// Three things live here. The notify events a state raises on entry and exit,
// including the ones a machine raises when it is deactivated mid-state. The
// condition gate, which parses `m_condition` once per object and answers false
// when it cannot — a wrong answer fires a wrong transition, so an unresolvable
// condition blocks rather than defaults. And the four machine-level event ids
// (`m_returnToPreviousStateEventId` and friends), which the vanilla player
// graph barely uses: of 530 machines in the two mt_behavior files, four name a
// random-transition event and none name the other three.

import Foundation

nonisolated extension BehaviorGraphInstance {
    // MARK: - Notify events

    /// Raises a state's `m_enterNotifyEvents` or `m_exitNotifyEvents`, in
    /// authored order.
    func raiseNotifyEvents(of stateId: Int, machine: HKBStateMachine, entering: Bool) {
        guard let entry = stateInfo(of: machine, id: stateId) else { return }
        let target = entering
            ? entry.info.enterNotifyEvents
            : entry.info.exitNotifyEvents
        guard
            let target,
            let array = object(at: target, as: HKBStateMachineEventPropertyArray.self)
        else {
            return
        }
        for event in array.events {
            raise(event)
        }
    }

    /// Raises one `hkbEventProperty`, payload included. An id of -1 is Havok's
    /// "no event" and is dropped by the queue.
    func raise(_ event: HKBEventProperty) {
        events.raise(id: event.id, payload: payload(at: event.payload))
    }

    /// The deactivation half of a machine's lifecycle: the state it was in
    /// raises its exit events, and the machine forgets that it was entered
    /// while keeping `currentStateId` for `m_startStateMode` 2.
    func noteMachineDeactivation(of machine: HKBStateMachine, at target: HKXPointerTarget) {
        guard var state = machineStates[target], state.isEntered else { return }
        raiseNotifyEvents(of: state.currentStateId, machine: machine, entering: false)
        state.isEntered = false
        state.transition = nil
        machineStates[target] = state
    }

    // MARK: - Conditions

    /// True when a transition's condition permits it to fire.
    ///
    /// `FLAG_DISABLE_CONDITION` is set by the exporter on every transition that
    /// carries no condition object, so it is checked first and the null pointer
    /// is a permit rather than a block. A condition that will not parse, or
    /// that names a variable this graph does not declare, blocks and is
    /// tallied.
    func isConditionMet(_ info: HKBStateMachineTransitionInfo) -> Bool {
        guard info.flags & BehaviorTransitionFlag.disableCondition == 0 else { return true }
        guard let target = info.condition else { return true }
        guard let expression = condition(at: target) else {
            tally.note(.transitionConditionUnparsed)
            return false
        }
        guard let result = expression.evaluate(in: variables) else {
            tally.note(.transitionConditionUnresolved)
            return false
        }
        return result
    }

    /// The parsed condition at `target`, cached. The optional is stored so a
    /// string that will not parse is parsed once and remembered as a failure.
    private func condition(at target: HKXPointerTarget) -> BehaviorConditionExpression? {
        if let cached = conditionCache[target] {
            return cached
        }
        let parsed = conditionSource(at: target).flatMap(BehaviorConditionExpression.parse)
        conditionCache[target] = parsed
        return parsed
    }

    private func conditionSource(at target: HKXPointerTarget) -> String? {
        if let expression = object(at: target, as: HKBExpressionCondition.self) {
            return expression.expression
        }
        return object(at: target, as: HKBStringCondition.self)?.conditionString
    }

    // MARK: - Trigger and initiate intervals

    /// True when the transition's authored window is open. A window is an event
    /// pair: it opens when `m_enterEventId` is raised and closes when
    /// `m_exitEventId` is. `m_enterTime` and `m_exitTime` are zero on every
    /// transition in the vanilla player graph, so a non-zero one is tallied
    /// rather than acted on.
    func isIntervalOpen(_ info: HKBStateMachineTransitionInfo) -> Bool {
        if info.flags & BehaviorTransitionFlag.useTriggerInterval != 0 {
            guard isOpen(info.triggerInterval) else { return false }
        }
        if info.flags & BehaviorTransitionFlag.useInitiateInterval != 0 {
            guard isOpen(info.initiateInterval) else { return false }
        }
        return true
    }

    private func isOpen(_ interval: HKBStateMachineTimeInterval) -> Bool {
        if interval.enterTime != 0 || interval.exitTime != 0 {
            tally.note(.transitionTimeIntervalIgnored)
        }
        guard interval.enterEventId >= 0 else { return true }
        guard let opened = eventLastSeen[interval.enterEventId] else { return false }
        guard
            interval.exitEventId >= 0,
            let closed = eventLastSeen[interval.exitEventId]
        else {
            return true
        }
        return opened > closed
    }

    // MARK: - Machine-level event transitions

    /// The four event ids a machine carries itself, checked only when no
    /// transition-info candidate fired. Each one cuts instantly: none of them
    /// names a transition effect.
    func selectMachineEventTransition(
        _ state: inout BehaviorMachineState,
        machine: HKBStateMachine
    ) {
        guard
            let stateId = machineEventStateId(machine, state: state),
            stateId != state.currentStateId,
            stateInfo(of: machine, id: stateId) != nil
        else {
            return
        }
        let cut: BehaviorTransition? = nil
        switchState(&state, to: stateId, machine: machine, transition: cut)
    }

    private func machineEventStateId(
        _ machine: HKBStateMachine,
        state: BehaviorMachineState
    ) -> Int? {
        if events.isActive(id: machine.returnToPreviousStateEventId), state.previousStateId >= 0 {
            return state.previousStateId
        }
        if events.isActive(id: machine.randomTransitionEventId) {
            return randomTransitionStateId(machine, state: state)
        }
        if events.isActive(id: machine.transitionToNextHigherStateEventId) {
            return neighbourStateId(machine, state: state, higher: true)
        }
        if events.isActive(id: machine.transitionToNextLowerStateEventId) {
            return neighbourStateId(machine, state: state, higher: false)
        }
        return nil
    }

    /// The "random" pick, made deterministic: the enabled state with the highest
    /// `m_probability`, ties broken by the lowest id. An engine that decides
    /// animation from an unseeded random source cannot be stepped twice with
    /// the same result, so the choice is fixed and tallied — the same call
    /// `BSEventEveryNEventsModifier` already makes.
    private func randomTransitionStateId(
        _ machine: HKBStateMachine,
        state: BehaviorMachineState
    ) -> Int? {
        tally.note(.stateMachineRandomTransitionFixed)
        var best: (id: Int, probability: Float)?
        for info in enabledStates(of: machine) where info.stateId != state.currentStateId {
            guard let current = best else {
                best = (info.stateId, info.probability)
                continue
            }
            if (info.probability, -info.stateId) > (current.probability, -current.id) {
                best = (info.stateId, info.probability)
            }
        }
        return best?.id
    }

    /// The next state id above or below the current one, wrapping when
    /// `m_wrapAroundStateId` says to.
    private func neighbourStateId(
        _ machine: HKBStateMachine,
        state: BehaviorMachineState,
        higher: Bool
    ) -> Int? {
        let ids = enabledStates(of: machine).map(\.stateId).sorted()
        guard !ids.isEmpty else { return nil }
        let ordered = higher ? ids : ids.reversed().map(\.self)
        let next = ordered.first {
            higher ? $0 > state.currentStateId : $0 < state.currentStateId
        }
        if let next {
            return next
        }
        return machine.wrapAroundStateId ? ordered.first : nil
    }

    private func enabledStates(of machine: HKBStateMachine) -> [HKBStateMachineStateInfo] {
        machine.states.compactMap(\.self)
            .compactMap { object(at: $0, as: HKBStateMachineStateInfo.self) }
            .filter(\.enable)
    }

    // MARK: - Reporting

    /// Publishes what this machine is doing, in names, in the order the walk
    /// reached the machines.
    func recordActiveState(_ machine: HKBStateMachine, state: BehaviorMachineState) {
        let current = stateInfo(of: machine, id: state.currentStateId)?.info.name
        let outgoing = state.transition
            .flatMap { stateInfo(of: machine, id: $0.fromStateId)?.info.name }
        activeStatesThisUpdate.append(
            BehaviorActiveState(
                machineName: machine.node.name,
                stateId: state.currentStateId,
                stateName: current,
                previousStateName: outgoing,
                blendWeight: state.transition?.weight ?? 1
            )
        )
    }
}
