// The parts of a running transition beyond one crossfade: a transition that interrupts
// another fades from that blend, a delayed one changes state when it ends, and a
// transition can require a nested state (docs/engine/behavior-state-machines.md).

import Foundation
import OpenSkyFormatsAnimation

nonisolated extension BehaviorGraphInstance {
    /// Steps the transition chain. A delayed transition changes state when it ends.
    func advanceTransition(
        _ state: inout BehaviorMachineState, machine: HKBStateMachine, deltaTime: Float
    ) {
        guard var transition = state.transition else { return }
        transition.advance(by: deltaTime)
        guard transition.isFinished else {
            state.transition = transition
            return
        }
        state.transition = nil
        if let destination = transition.delayedStateId {
            switchState(&state, to: destination, machine: machine, transition: nil)
        }
    }

    /// What `transition` fades from: the transition it interrupted, still running, or
    /// else its source state. `poses` holds each state already posed this update, so a
    /// state two blends share advances once.
    func sourcePose(
        of transition: BehaviorTransition,
        machine: HKBStateMachine,
        depth: Int,
        deltaTime: Float,
        poses: inout [Int: BehaviorPose]
    ) -> BehaviorPose {
        guard let inner = transition.interrupted.first else {
            return sharedStatePose(
                transition.fromStateId, machine: machine, depth: depth, deltaTime: deltaTime,
                poses: &poses
            )
        }
        let outgoing = sourcePose(
            of: inner, machine: machine, depth: depth, deltaTime: deltaTime, poses: &poses
        )
        let incoming = sharedStatePose(
            inner.delayedStateId ?? transition.fromStateId,
            machine: machine, depth: depth, deltaTime: deltaTime, poses: &poses
        )
        return blendFull(outgoing, incoming, weight: inner.weight)
    }

    func sharedStatePose(
        _ stateId: Int,
        machine: HKBStateMachine,
        depth: Int,
        deltaTime: Float,
        poses: inout [Int: BehaviorPose]
    ) -> BehaviorPose {
        if let posed = poses[stateId] {
            return posed
        }
        let pose = statePose(stateId, machine: machine, depth: depth, deltaTime: deltaTime)
        poses[stateId] = pose
        return pose
    }

    /// `FLAG_FROM_NESTED_STATE_ID_IS_VALID`: the machine inside the current state must
    /// be in `m_fromNestedStateId`.
    func isNestedSourceMet(
        _ info: HKBStateMachineTransitionInfo,
        machine: HKBStateMachine,
        state: BehaviorMachineState
    ) -> Bool {
        guard info.flags & BehaviorTransitionFlag.fromNestedStateIsValid != 0 else { return true }
        guard
            let generator = stateInfo(of: machine, id: state.currentStateId)?.info.generator,
            object(at: generator, as: HKBStateMachine.self) != nil,
            let nested = machineStates[generator], nested.isEntered
        else { return false }
        return nested.currentStateId == info.fromNestedStateId
    }

    /// The transitions the random event may pick: the current state's and the wildcards,
    /// passing the usual rules but for the event, and not barred from random picks.
    func randomCandidates(
        machine: HKBStateMachine, state: BehaviorMachineState
    ) -> [HKBStateMachineTransitionInfo] {
        candidates(machine: machine, state: state).map(\.info).filter { info in
            let barred = BehaviorTransitionFlag.disabled
                | BehaviorTransitionFlag.disallowRandomTransition
            let allowsSelf = info.flags & BehaviorTransitionFlag.allowSelfTransition != 0
            return info.flags & barred == 0
                && (info.toStateId != state.currentStateId || allowsSelf)
                && stateInfo(of: machine, id: info.toStateId) != nil
                && isIntervalOpen(info) && isConditionMet(info)
                && isNestedSourceMet(info, machine: machine, state: state)
        }
    }
}
