// `hkbStateMachine` evaluation: one current state and at most one transition in
// flight. The state changes at once; the blend only fades the old pose.
// `FLAG_DELAY_STATE_CHANGE` (14 of 3,769 vanilla transitions) is tallied. Order:
// highest `m_priority`, state transitions before wildcards, then array order. That
// tie-break is ours, and a global wildcard below another state comes after both
// (docs/engine/behavior-state-machines.md).

import Foundation
public import OpenSkyFormatsAnimation

/// One transition the update may fire, with where it was found.
nonisolated struct BehaviorTransitionCandidate: Sendable {
    let info: HKBStateMachineTransitionInfo
    let isWildcard: Bool

    /// Higher sorts first. A state's own transition outranks a wildcard of the
    /// same priority.
    var rank: (Int, Int) {
        (info.priority, isWildcard ? 0 : 1)
    }
}

nonisolated extension BehaviorGraphInstance.StateMachines {
    /// Runs one state machine: enter, step the crossfade, pick a transition,
    /// then pose the current state and whatever is still blending out.
    func evaluateStateMachine(
        _ machine: HKBStateMachine,
        _ visit: BehaviorVisit,
        deltaTime: Float
    ) -> BehaviorPose {
        let (target, bound, depth) = (visit.target, visit.bound, visit.depth)
        var state = graph.machineMemory.machineStates[target] ?? BehaviorMachineState()
        if !state.isEntered {
            enterStartState(&state, machine: machine, bound: bound)
        }
        selectTransition(&state, machine: machine, at: target)
        // The clock runs after selection, so a transition that starts this
        // update already shows one step of its crossfade rather than a frame of
        // the pose it is leaving, and one that reaches its duration is dropped
        // here rather than posed at a weight of exactly 1.
        advanceTransition(&state, machine: machine, deltaTime: deltaTime)
        graph.machineMemory.machineStates[target] = state
        publishMachineOutputs(machine, at: target, currentStateId: state.currentStateId)
        // Reported before the pose walk rather than after it, so a machine
        // appears ahead of the machines nested below it.
        recordActiveState(machine, state: state)
        let pose = machinePose(
            state, machine: machine, depth: depth, deltaTime: deltaTime
        )
        graph.pendingNestedStateIds = []
        return pose
    }

    // MARK: - Entering

    /// Places a newly active machine on its start state. Mode 0 uses `m_startStateId`
    /// (with bindings), mode 1 `m_syncVariableIndex`, mode 2 a random state by
    /// `m_probability`. A transition into a nested state overrides all three.
    private func enterStartState(
        _ state: inout BehaviorMachineState,
        machine: HKBStateMachine,
        bound: [String: BehaviorVariableValue]
    ) {
        var stateId = bound.int("startStateId", or: machine.startStateId)
        if
            machine.startStateMode == BehaviorStartStateMode.sync,
            let synced = graph.variables.value(at: machine.syncVariableIndex)
        {
            stateId = synced.intValue
        }
        if
            machine.startStateMode == BehaviorStartStateMode.random,
            let picked = randomStartStateId(machine)
        {
            stateId = picked
        }
        if let nested = graph.pendingNestedStateIds.first {
            stateId = nested
            graph.pendingNestedStateIds.removeFirst()
        }
        // A missing or disabled start state falls back to the first enabled state.
        if stateInfo(of: machine, id: stateId) == nil, let first = firstEnabledStateId(machine) {
            stateId = first
        }
        state.isEntered = true
        state.previousStateId = -1
        state.currentStateId = stateId
        state.transition = nil
        guard stateInfo(of: machine, id: stateId) != nil else {
            graph.tally.note(.stateMachineNoStartState)
            return
        }
        graph.raise(machine.eventToSendWhenStateOrTransitionChanges)
        raiseNotifyEvents(of: stateId, machine: machine, entering: true)
    }

    /// The enabled state with `id`, and where it lives.
    func stateInfo(
        of machine: HKBStateMachine,
        id: Int
    ) -> (target: HKXPointerTarget, info: HKBStateMachineStateInfo)? {
        for case let stateTarget? in machine.states {
            guard
                let info = graph.object(at: stateTarget, as: HKBStateMachineStateInfo.self),
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
        // The outgoing walk must not use up or clear the start states the
        // transition handed to the incoming state's machines.
        let pending = graph.pendingNestedStateIds
        var poses: [Int: BehaviorPose] = [:]
        let outgoing = sourcePose(
            of: transition, in: BehaviorMachineWalk(
                machine: machine,
                depth: depth,
                deltaTime: deltaTime
            ), poses: &poses
        )
        graph.pendingNestedStateIds = pending
        if transition.synchronizes {
            let source = stateInfo(of: machine, id: transition.fromStateId)?.info.generator
            graph.pendingClipPhase = graph.clipPlayback.clipPhase(under: source).map { ($0, true) }
        }
        let incoming = sharedStatePose(
            transition.delayedStateId ?? state.currentStateId,
            in: BehaviorMachineWalk(machine: machine, depth: depth, deltaTime: deltaTime),
            poses: &poses
        )
        graph.pendingClipPhase = nil
        return graph.blenders.blendFull(outgoing, incoming, weight: transition.weight)
    }

    func statePose(
        _ stateId: Int,
        machine: HKBStateMachine,
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        guard let entry = stateInfo(of: machine, id: stateId) else {
            return graph.skeleton.restPose
        }
        graph.markReached(entry.target)
        return graph.evaluateGenerator(
            at: entry.info.generator, depth: depth, deltaTime: deltaTime
        )
    }

    // MARK: - Transition selection

    /// Picks and starts at most one transition per update.
    private func selectTransition(
        _ state: inout BehaviorMachineState,
        machine: HKBStateMachine,
        at target: HKXPointerTarget
    ) {
        if let transition = state.transition, transition.isUninterruptibleWhilePlaying {
            return
        }
        guard let choice = bestCandidate(machine: machine, state: state) else {
            if !selectGlobalWildcard(&state, machine: machine, at: target) {
                selectMachineEventTransition(&state, machine: machine)
            }
            return
        }
        if let transition = state.transition, transition.refuses(choice.info) {
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
    func candidates(
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
            let array = graph.object(at: target, as: HKBStateMachineTransitionInfoArray.self)
        else {
            return []
        }
        graph.markReached(target)
        return array.transitions
    }

    private func isEligible(
        _ candidate: BehaviorTransitionCandidate,
        machine: HKBStateMachine,
        state: BehaviorMachineState
    ) -> Bool {
        let info = candidate.info
        guard
            info.flags & BehaviorTransitionFlag.disabled == 0,
            graph.events.isActive(id: info.eventId) else { return false }
        let isSelf = info.toStateId == state.currentStateId
        let allowsSelf = info.flags & BehaviorTransitionFlag.allowSelfTransition != 0
        guard
            !isSelf || allowsSelf, stateInfo(of: machine, id: info.toStateId) != nil,
            isIntervalOpen(info), isNestedSourceMet(info, machine: machine, state: state)
        else { return false }
        return isConditionMet(info)
    }

    // MARK: - Starting a transition

    private func begin(
        _ candidate: BehaviorTransitionCandidate,
        in state: inout BehaviorMachineState,
        machine: HKBStateMachine
    ) {
        let info = candidate.info
        let running = state.transition
        guard var effect = effect(for: info) else {
            // A transition with no effect ends every blend and switches at once.
            switchState(&state, to: info.toStateId, machine: machine, transition: nil)
            notePendingNested(info)
            return
        }
        effect.priority = info.priority
        effect.interrupted = running.map { [$0] } ?? []
        effect.trim(to: machine.maxSimultaneousTransitions)
        if info.flags & BehaviorTransitionFlag.delayStateChange != 0 {
            effect.fromStateId = state.currentStateId
            effect.delayedStateId = info.toStateId
            state.transition = effect
        } else {
            switchState(&state, to: info.toStateId, machine: machine, transition: effect)
        }
        notePendingNested(info)
    }

    private func notePendingNested(_ info: HKBStateMachineTransitionInfo) {
        if info.flags & BehaviorTransitionFlag.toNestedStateIsValid != 0 {
            graph.pendingNestedStateIds = [info.toNestedStateId]
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
        restartGenerator(ofState: stateId, leaving: state.currentStateId, machine: machine)
        var effect = transition
        effect?.fromStateId = state.currentStateId
        state.previousStateId = state.currentStateId
        state.currentStateId = stateId
        state.transition = effect
        graph.raise(machine.eventToSendWhenStateOrTransitionChanges)
        raiseNotifyEvents(of: stateId, machine: machine, entering: true)
    }

    /// The crossfade a transition's `hkbTransitionEffect` asks for, or nil when
    /// it asks for an instant cut — a null pointer, or a zero duration, which is
    /// what 198 of the 397 blending effects in the vanilla player graph carry.
    func effect(for info: HKBStateMachineTransitionInfo) -> BehaviorTransition? {
        guard let target = info.transition else { return nil }
        guard let blending = graph.object(at: target, as: HKBBlendingTransitionEffect.self) else {
            graph.tally.note(.transitionEffectUnevaluated)
            return nil
        }
        graph.markReached(target)
        guard blending.duration > 0 else { return nil }
        if !BehaviorBlendCurve.isKnown(blending.blendCurve) {
            graph.tally.note(.transitionBlendCurveApproximated)
        }
        if blending.toGeneratorStartTimeFraction != 0 {
            graph.tally.note(.transitionStartFractionIgnored)
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
