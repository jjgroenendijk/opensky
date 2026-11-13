// The event and condition half of state-machine evaluation: enter and exit notify
// events, the condition gate (an unparsable `m_condition` blocks, so no wrong transition
// fires), and the four machine-level event ids, which vanilla barely uses.

import Foundation
import OpenSkyFormatsAnimation

nonisolated extension BehaviorGraphInstance.StateMachines {
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
            let array = graph.object(at: target, as: HKBStateMachineEventPropertyArray.self)
        else {
            return
        }
        for event in array.events {
            graph.raise(event)
        }
    }

    /// The deactivation half of a machine's lifecycle: the state it was in
    /// raises its exit events, and the machine forgets that it was entered
    /// while keeping `currentStateId` for `m_startStateMode` 2.
    func noteMachineDeactivation(of machine: HKBStateMachine, at target: HKXPointerTarget) {
        guard var state = graph.machineMemory.machineStates[target], state.isEntered else { return }
        raiseNotifyEvents(of: state.currentStateId, machine: machine, entering: false)
        state.isEntered = false
        state.transition = nil
        graph.machineMemory.machineStates[target] = state
        publishMachineDeactivation(at: target)
    }

    // MARK: - Conditions

    /// True when a transition's condition permits it. `FLAG_DISABLE_CONDITION` marks
    /// "no condition" and is checked first. An unparsable condition or unknown variable
    /// blocks and is tallied.
    func isConditionMet(_ info: HKBStateMachineTransitionInfo) -> Bool {
        guard
            info.flags & BehaviorTransitionFlag.disableCondition == 0,
            let target = info.condition else { return true }
        guard let expression = condition(at: target) else {
            graph.tally.note(.transitionConditionUnparsed, text: conditionSource(at: target))
            return false
        }
        guard let result = expression.evaluate(in: graph.variables) else {
            graph.tally.note(.transitionConditionUnresolved)
            return false
        }
        return result
    }

    /// The parsed condition at `target`, cached. The optional is stored so a
    /// string that will not parse is parsed once and remembered as a failure.
    private func condition(at target: HKXPointerTarget) -> BehaviorConditionExpression? {
        if let cached = graph.machineMemory.conditionCache[target] {
            return cached
        }
        let parsed = conditionSource(at: target).flatMap(BehaviorConditionExpression.parse)
        graph.machineMemory.conditionCache[target] = parsed
        return parsed
    }

    private func conditionSource(at target: HKXPointerTarget) -> String? {
        if let expression = graph.object(at: target, as: HKBExpressionCondition.self) {
            return expression.expression
        }
        return graph.object(at: target, as: HKBStringCondition.self)?.conditionString
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
            graph.tally.note(.transitionTimeIntervalIgnored)
        }
        guard interval.enterEventId >= 0 else { return true }
        guard let opened = graph.eventLastSeen[interval.enterEventId] else { return false }
        guard
            interval.exitEventId >= 0,
            let closed = graph.eventLastSeen[interval.exitEventId]
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
        if
            graph.events.isActive(id: machine.returnToPreviousStateEventId),
            state.previousStateId >= 0,
            state.previousStateId != state.currentStateId
        {
            return state.previousStateId
        }
        if graph.events.isActive(id: machine.randomTransitionEventId) {
            return randomTransitionStateId(machine, state: state)
        }
        if graph.events.isActive(id: machine.transitionToNextHigherStateEventId) {
            return neighbourStateId(machine, state: state, higher: true)
        }
        if graph.events.isActive(id: machine.transitionToNextLowerStateEventId) {
            return neighbourStateId(machine, state: state, higher: false)
        }
        return nil
    }

    /// The random event's pick: the targets of the current state's transitions and the
    /// wildcards that pass the usual rules and allow a random pick, weighted by the target
    /// state's `m_probability`.
    private func randomTransitionStateId(
        _ machine: HKBStateMachine,
        state: BehaviorMachineState
    ) -> Int? {
        let targets = randomCandidates(machine: machine, state: state).compactMap { info in
            stateInfo(of: machine, id: info.toStateId)?.info
        }
        return graph.machineMemory.stateMachineRandom
            .pick(targets.map { ($0.stateId, $0.probability) })
    }

    /// A random start state among the enabled states, by `m_probability`.
    func randomStartStateId(_ machine: HKBStateMachine) -> Int? {
        graph.machineMemory.stateMachineRandom
            .pick(enabledStates(of: machine).map { ($0.stateId, $0.probability) })
    }

    func firstEnabledStateId(_ machine: HKBStateMachine) -> Int? {
        enabledStates(of: machine).first?.stateId
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
            .compactMap { graph.object(at: $0, as: HKBStateMachineStateInfo.self) }
            .filter(\.enable)
    }

    // MARK: - Reporting

    /// Publishes what this machine is doing, in names, in the order the walk
    /// reached the machines.
    func recordActiveState(_ machine: HKBStateMachine, state: BehaviorMachineState) {
        let current = stateInfo(of: machine, id: state.currentStateId)?.info.name
        let outgoing = state.transition
            .flatMap { stateInfo(of: machine, id: $0.fromStateId)?.info.name }
        graph.activeStatesThisUpdate.append(
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

/// `m_startStateMode` values.
nonisolated enum BehaviorStartStateMode {
    static let sync = 1
    static let random = 2
}

/// The state machines' random source: a 32-bit linear congruential generator.
/// [WARNING] The seed is OpenSky's choice; the game seeds one per character.
nonisolated struct BehaviorStateMachineRandom: Equatable, Sendable {
    private var state: UInt32

    init(seed: UInt32 = 0x5EED) {
        state = seed
    }

    /// A value in [0, 1).
    mutating func next() -> Float {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Float(Double(state) / 4_294_967_296)
    }

    /// The id whose share of the summed probability covers the drawn value.
    mutating func pick(_ weighted: [(id: Int, probability: Float)]) -> Int? {
        Self.pick(weighted, roll: next())
    }

    /// The entry whose share of the summed weights holds `roll`, a value in 0..<1.
    static func pick(_ weighted: [(id: Int, probability: Float)], roll: Float) -> Int? {
        let total = weighted.reduce(Float(0)) { $0 + max($1.probability, 0) }
        guard total > 0 else { return weighted.first?.id }
        let drawn = roll * total
        var sum: Float = 0
        for entry in weighted {
            sum += max(entry.probability, 0)
            if drawn < sum {
                return entry.id
            }
        }
        return weighted.last?.id
    }
}
