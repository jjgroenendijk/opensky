// Modifier evaluation. Only modifiers computable from evaluator state are run: lists,
// event wrapping, timers, deactivation events and event counting. Others pass the pose
// through with a `BehaviorTally.passthroughModifiers` entry, which is the worklist. A
// missing foot-IK reads as a foot that does not plant, not an invented one.

import Foundation
import OpenSkyFormatsAnimation

nonisolated extension BehaviorGraphInstance {
    /// Runs the modifier at `target` over `pose`. Modifiers that only touch
    /// variables and events return the pose unchanged, which is not a
    /// pass-through and is not tallied as one.
    public func applyModifier(
        at target: HKXPointerTarget?,
        to pose: BehaviorPose,
        deltaTime: Float,
        depth: Int = 0
    ) -> BehaviorPose {
        guard let target, depth < Self.maximumDepth else {
            if target != nil {
                tally.note(.depthCapReached)
            }
            return pose
        }
        guard let node = compiledNode(at: target) else { return pose }
        markReached(target)
        tally.noteModifier()
        guard isEnabled(node.object), !isDisabled(node) else { return pose }
        return run(node.object, at: target, to: pose, deltaTime: deltaTime, depth: depth)
    }

    /// `hkbModifier::m_enable`, read through the class header each modifier
    /// carries. A class that is not a modifier at all counts as enabled.
    private func isEnabled(_ object: any HKBClass) -> Bool {
        switch object {
        case let value as HKBModifierList: value.modifier.enable
        case let value as HKBEventDrivenModifier: value.modifier.enable
        case let value as HKBTimerModifier: value.modifier.enable
        case let value as BSEventOnDeactivateModifier: value.modifier.enable
        case let value as BSEventEveryNEventsModifier: value.modifier.enable
        case let value as HKBPoweredRagdollControlsModifier: value.modifier.enable
        case let value as BSRagdollContactListenerModifier: value.modifier.enable
        default: true
        }
    }

    private func run(
        _ object: any HKBClass,
        at target: HKXPointerTarget,
        to pose: BehaviorPose,
        deltaTime: Float,
        depth: Int
    ) -> BehaviorPose {
        switch object {
        case let list as HKBModifierList:
            var result = pose
            for child in list.modifiers.compactMap(\.self) {
                result = applyModifier(
                    at: child, to: result, deltaTime: deltaTime, depth: depth + 1
                )
            }
            return result
        case let driven as HKBEventDrivenModifier:
            return applyEventDriven(
                driven, at: target, to: pose, deltaTime: deltaTime, depth: depth
            )
        case let timer as HKBTimerModifier:
            applyTimer(timer, at: target, deltaTime: deltaTime)
            return pose
        case is BSEventOnDeactivateModifier:
            // The event fires on deactivation, which `noteDeactivation` below
            // handles; while running there is nothing to do.
            return pose
        case let counter as BSEventEveryNEventsModifier:
            applyEventCounter(counter, at: target)
            return pose
        case let controls as HKBRigidBodyRagdollControlsModifier:
            applyRagdollControls(controls)
            return pose
        case let powered as HKBPoweredRagdollControlsModifier:
            poweredRagdollControls = powered
            return pose
        case let listener as BSRagdollContactListenerModifier:
            let id = listener.contactEvent.id
            ragdollContactEvent = events.names.indices.contains(id) ? events.names[id] : nil
            return pose
        default:
            tally.notePassthroughModifier(object.className)
            return pose
        }
    }

    // MARK: - Implemented modifiers

    /// `hkbEventDrivenModifier`: runs its wrapped modifier only while active.
    /// `m_activateEventId` starts it, `m_deactivateEventId` stops it, and
    /// `m_activeByDefault` sets the state it starts in.
    private func applyEventDriven(
        _ driven: HKBEventDrivenModifier,
        at target: HKXPointerTarget,
        to pose: BehaviorPose,
        deltaTime: Float,
        depth: Int
    ) -> BehaviorPose {
        var state = markReached(target)
        if !state.hasSeeded {
            state.hasSeeded = true
            state.isModifierRunning = driven.activeByDefault
        }
        if events.isActive(id: driven.activateEventId) {
            state.isModifierRunning = true
        }
        if events.isActive(id: driven.deactivateEventId) {
            state.isModifierRunning = false
        }
        nodeStates[target] = state
        guard state.isModifierRunning else { return pose }
        return applyModifier(
            at: driven.wrapped, to: pose, deltaTime: deltaTime, depth: depth + 1
        )
    }

    /// `hkbTimerModifier`: raises `m_alarmEvent` once `m_alarmTimeSeconds` have
    /// passed since activation, then stays quiet until it is reactivated.
    private func applyTimer(
        _ timer: HKBTimerModifier,
        at target: HKXPointerTarget,
        deltaTime: Float
    ) {
        var state = markReached(target)
        state.elapsed += deltaTime
        if !state.hasFiredAlarm, state.elapsed >= timer.alarmTimeSeconds {
            state.hasFiredAlarm = true
            events.raise(
                id: timer.alarmEvent.id, payload: payload(at: timer.alarmEvent.payload)
            )
        }
        nodeStates[target] = state
    }

    /// `BSEventEveryNEventsModifier`: counts occurrences of
    /// `m_eventToCheckFor` and raises `m_eventToSend` every N of them.
    /// `m_randomizeNumberOfEvents` is honoured as its non-random maximum,
    /// because an engine that decides animation timing from an unseeded random
    /// source cannot be stepped deterministically; the choice is tallied.
    private func applyEventCounter(
        _ counter: BSEventEveryNEventsModifier,
        at target: HKXPointerTarget
    ) {
        var state = markReached(target)
        let occurrences = events.active.count { $0.id == counter.eventToCheckFor.id }
        guard occurrences > 0 else {
            nodeStates[target] = state
            return
        }
        if counter.randomizeNumberOfEvents {
            tally.notePassthroughModifier(BSEventEveryNEventsModifier.className)
        }
        let threshold = max(counter.numberOfEventsBeforeSend, 1)
        state.eventCount += occurrences
        while state.eventCount >= threshold {
            state.eventCount -= threshold
            events.raise(
                id: counter.eventToSend.id,
                payload: payload(at: counter.eventToSend.payload)
            )
        }
        nodeStates[target] = state
    }

    /// `hkbRigidBodyRagdollControlsModifier`: publishes the authored blend duration so
    /// `RagdollRuntime` uses it. `m_bones` is not read; the ragdoll uses every body in
    /// the skeleton NIF.
    private func applyRagdollControls(_ controls: HKBRigidBodyRagdollControlsModifier) {
        ragdollBlendDuration = controls.durationToBlend
    }

    // MARK: - Deactivation

    /// Runs a node's deactivation: `BSEventOnDeactivateModifier` raises its event, and
    /// `hkbStateMachine` leaves its state.
    public func noteDeactivation(of object: any HKBClass, at target: HKXPointerTarget) {
        if let machine = object as? HKBStateMachine {
            noteMachineDeactivation(of: machine, at: target)
            return
        }
        guard
            let modifier = object as? BSEventOnDeactivateModifier,
            modifier.modifier.enable
        else {
            return
        }
        events.raise(id: modifier.event.id, payload: payload(at: modifier.event.payload))
    }
}
