// `hkbStateMachine` evaluation (issue #330): entering a start state, running
// the current state's generator, and choosing the transition an event fires.
//
// The model is one current state plus at most one transition in flight. When a
// transition starts, the state change happens immediately — `currentStateId`
// becomes the destination and the destination's enter events are raised — and
// the `hkbBlendingTransitionEffect` only fades the outgoing pose away. That is
// why `FLAG_DELAY_STATE_CHANGE` exists as a separate authored flag: the default
// is not delayed. It is set on 14 of the 3,769 transitions in the vanilla
// player graph, and this evaluator tallies rather than honours it.
//
// Selection order is total, so two instances stepped with the same events pick
// the same transition: highest `m_priority` first, a state's own transitions
// ahead of the machine's wildcards at equal priority, and array order ahead of
// everything at equal priority and kind. Havok's own tie-break is not documented
// in any source consulted here, so this is a decision, recorded in
// `docs/engine/behavior-runtime.md`.

import Foundation

/// One transition the update may fire, with where it was found.
nonisolated struct BehaviorTransitionCandidate {
    let info: HKBStateMachineTransitionInfo
    let isWildcard: Bool

    /// Higher sorts first. A state's own transition outranks a wildcard of the
    /// same priority.
    var rank: (Int, Int) {
        (info.priority, isWildcard ? 0 : 1)
    }
}

nonisolated extension BehaviorGraphInstance {
    /// Runs one state machine: enter, step the crossfade, pick a transition,
    /// then pose the current state and whatever is still blending out.
    func evaluateStateMachine(
        _ machine: HKBStateMachine,
        at target: HKXPointerTarget,
        bound: [String: BehaviorVariableValue],
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        var state = machineStates[target] ?? BehaviorMachineState()
        if !state.isEntered {
            enterStartState(&state, machine: machine, bound: bound)
        }
        selectTransition(&state, machine: machine)
        // The clock runs after selection, so a transition that starts this
        // update already shows one step of its crossfade rather than a frame of
        // the pose it is leaving, and one that reaches its duration is dropped
        // here rather than posed at a weight of exactly 1.
        if var transition = state.transition {
            transition.elapsed += max(deltaTime, 0)
            state.transition = transition.isFinished ? nil : transition
        }
        machineStates[target] = state
        // Reported before the pose walk rather than after it, so a machine
        // appears ahead of the machines nested below it.
        recordActiveState(machine, state: state)
        let pose = machinePose(
            state, machine: machine, depth: depth, deltaTime: deltaTime
        )
        pendingNestedStateId = nil
        return pose
    }

    // MARK: - Entering

    /// Places a freshly activated machine on its start state.
    ///
    /// `m_startStateMode` 0 uses `m_startStateId`, honouring a binding on it —
    /// which the vanilla data leans on heavily. Mode 1 reads the id out of
    /// `m_syncVariableIndex`. Mode 2 re-enters whatever was current when the
    /// machine was last deactivated, which is why `BehaviorMachineState`
    /// outlives node state. A transition into a nested state overrides all
    /// three.
    private func enterStartState(
        _ state: inout BehaviorMachineState,
        machine: HKBStateMachine,
        bound: [String: BehaviorVariableValue]
    ) {
        var stateId = bound.int("startStateId", or: machine.startStateId)
        if
            machine.startStateMode == 1,
            let synced = variables.value(at: machine.syncVariableIndex)
        {
            stateId = synced.intValue
        }
        if machine.startStateMode == 2, state.currentStateId >= 0 {
            stateId = state.currentStateId
        }
        if let nested = pendingNestedStateId {
            stateId = nested
            pendingNestedStateId = nil
        }
        state.isEntered = true
        state.previousStateId = -1
        state.currentStateId = stateId
        state.transition = nil
        guard stateInfo(of: machine, id: stateId) != nil else {
            tally.note(.stateMachineNoStartState)
            return
        }
        raise(machine.eventToSendWhenStateOrTransitionChanges)
        raiseNotifyEvents(of: stateId, machine: machine, entering: true)
    }

    /// The enabled state with `id`, and where it lives.
    func stateInfo(
        of machine: HKBStateMachine,
        id: Int
    ) -> (target: HKXPointerTarget, info: HKBStateMachineStateInfo)? {
        for stateTarget in machine.states.compactMap(\.self) {
            guard
                let info = object(at: stateTarget, as: HKBStateMachineStateInfo.self),
                info.stateId == id, info.enable
            else {
                continue
            }
            return (stateTarget, info)
        }
        return nil
    }

    // MARK: - Posing

    /// The machine's pose: the current state, crossfaded with the state it is
    /// blending out of while a transition is in flight.
    private func machinePose(
        _ state: BehaviorMachineState,
        machine: HKBStateMachine,
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        guard let transition = state.transition, !transition.ignoresFromGenerator else {
            return statePose(
                state.currentStateId, machine: machine, depth: depth, deltaTime: deltaTime
            )
        }
        let outgoing = statePose(
            transition.fromStateId, machine: machine, depth: depth, deltaTime: deltaTime
        )
        if transition.synchronizes {
            let source = stateInfo(of: machine, id: transition.fromStateId)?.info.generator
            pendingClipPhase = clipPhase(under: source).map { ($0, true) }
        }
        let incoming = statePose(
            state.currentStateId, machine: machine, depth: depth, deltaTime: deltaTime
        )
        pendingClipPhase = nil
        return BehaviorPoseMath.blend(outgoing, incoming, weight: transition.weight)
    }

    private func statePose(
        _ stateId: Int,
        machine: HKBStateMachine,
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        guard let entry = stateInfo(of: machine, id: stateId) else {
            return skeleton.restPose
        }
        markReached(entry.target)
        return evaluateGenerator(
            at: entry.info.generator, depth: depth, deltaTime: deltaTime
        )
    }

    // MARK: - Transition selection

    /// Picks and starts at most one transition per update.
    private func selectTransition(
        _ state: inout BehaviorMachineState,
        machine: HKBStateMachine
    ) {
        if let transition = state.transition, transition.isUninterruptible {
            return
        }
        guard let choice = bestCandidate(machine: machine, state: state) else {
            selectMachineEventTransition(&state, machine: machine)
            return
        }
        begin(choice, in: &state, machine: machine)
    }

    private func bestCandidate(
        machine: HKBStateMachine,
        state: BehaviorMachineState
    ) -> BehaviorTransitionCandidate? {
        var best: BehaviorTransitionCandidate?
        for candidate in candidates(machine: machine, state: state) {
            guard isEligible(candidate, machine: machine, state: state) else { continue }
            guard let current = best else {
                best = candidate
                continue
            }
            if candidate.rank > current.rank {
                best = candidate
            }
        }
        return best
    }

    /// The current state's transitions, then the machine's wildcards.
    private func candidates(
        machine: HKBStateMachine,
        state: BehaviorMachineState
    ) -> [BehaviorTransitionCandidate] {
        let own = stateInfo(of: machine, id: state.currentStateId)?.info.transitions
        return transitions(at: own).map {
            BehaviorTransitionCandidate(info: $0, isWildcard: false)
        } + transitions(at: machine.wildcardTransitions).map {
            BehaviorTransitionCandidate(info: $0, isWildcard: true)
        }
    }

    private func transitions(at target: HKXPointerTarget?) -> [HKBStateMachineTransitionInfo] {
        guard
            let target,
            let array = object(at: target, as: HKBStateMachineTransitionInfoArray.self)
        else {
            return []
        }
        markReached(target)
        return array.transitions
    }

    private func isEligible(
        _ candidate: BehaviorTransitionCandidate,
        machine: HKBStateMachine,
        state: BehaviorMachineState
    ) -> Bool {
        let info = candidate.info
        guard info.flags & BehaviorTransitionFlag.disabled == 0 else { return false }
        guard events.isActive(id: info.eventId) else { return false }
        let isSelf = info.toStateId == state.currentStateId
        let allowsSelf = info.flags & BehaviorTransitionFlag.allowSelfTransition != 0
        guard !isSelf || allowsSelf else { return false }
        guard stateInfo(of: machine, id: info.toStateId) != nil else { return false }
        guard isIntervalOpen(info) else { return false }
        return isConditionMet(info)
    }

    // MARK: - Starting a transition

    private func begin(
        _ candidate: BehaviorTransitionCandidate,
        in state: inout BehaviorMachineState,
        machine: HKBStateMachine
    ) {
        let info = candidate.info
        if state.transition != nil {
            tally.note(.stateMachineTransitionInterrupted)
        }
        if info.flags & BehaviorTransitionFlag.delayStateChange != 0 {
            tally.note(.transitionStateChangeNotDelayed)
        }
        if info.flags & BehaviorTransitionFlag.fromNestedStateIsValid != 0 {
            tally.note(.transitionFromNestedStateIgnored)
        }
        switchState(
            &state, to: info.toStateId, machine: machine, transition: effect(for: info)
        )
        if info.flags & BehaviorTransitionFlag.toNestedStateIsValid != 0 {
            pendingNestedStateId = info.toNestedStateId
        }
    }

    /// The common half of every state change: exit events, the id swap, enter
    /// events, and the machine's own change event.
    func switchState(
        _ state: inout BehaviorMachineState,
        to stateId: Int,
        machine: HKBStateMachine,
        transition: BehaviorTransition?
    ) {
        raiseNotifyEvents(of: state.currentStateId, machine: machine, entering: false)
        var effect = transition
        effect?.fromStateId = state.currentStateId
        state.previousStateId = state.currentStateId
        state.currentStateId = stateId
        state.transition = effect
        raise(machine.eventToSendWhenStateOrTransitionChanges)
        raiseNotifyEvents(of: stateId, machine: machine, entering: true)
    }

    /// The crossfade a transition's `hkbTransitionEffect` asks for, or nil when
    /// it asks for an instant cut — a null pointer, or a zero duration, which is
    /// what 198 of the 397 blending effects in the vanilla player graph carry.
    private func effect(for info: HKBStateMachineTransitionInfo) -> BehaviorTransition? {
        guard let target = info.transition else { return nil }
        guard let blending = object(at: target, as: HKBBlendingTransitionEffect.self) else {
            tally.note(.transitionEffectUnevaluated)
            return nil
        }
        markReached(target)
        guard blending.duration > 0 else { return nil }
        if !BehaviorBlendCurve.isKnown(blending.blendCurve) {
            tally.note(.transitionBlendCurveApproximated)
        }
        if blending.toGeneratorStartTimeFraction != 0 {
            tally.note(.transitionStartFractionIgnored)
        }
        return BehaviorTransition(
            fromStateId: -1,
            elapsed: 0,
            duration: blending.duration,
            blendCurve: blending.blendCurve,
            effectFlags: blending.flags,
            transitionFlags: info.flags
        )
    }
}
