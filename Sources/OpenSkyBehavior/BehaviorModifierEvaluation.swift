// Modifier evaluation: the routing, the list and event modifiers, and deactivation.
// The variable modifiers are in `BehaviorVariableModifiers.swift`, the bone modifiers
// in `BehaviorBoneModifiers.swift` and `BehaviorAimModifiers.swift`. A class with no
// semantics passes the pose through with a `BehaviorTally.passthroughModifiers` entry.

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
        let bound = boundValues(of: node)
        guard bound.bool("enable", or: isEnabled(node.object)), !isDisabled(node) else {
            return pose
        }
        let step = BehaviorModifierStep(
            target: target, node: node, bound: bound, deltaTime: deltaTime, depth: depth
        )
        return run(node.object, step, to: pose)
    }

    /// `hkbModifier::m_enable`. A class that is not a modifier at all counts as enabled.
    private func isEnabled(_ object: any HKBClass) -> Bool {
        (object as? any HKBModifierClass)?.modifier.enable ?? true
    }

    private func run(
        _ object: any HKBClass,
        _ step: BehaviorModifierStep,
        to pose: BehaviorPose
    ) -> BehaviorPose {
        let target = step.target
        switch object {
        case let list as HKBModifierList:
            var result = pose
            for child in list.modifiers.compactMap(\.self) {
                result = applyModifier(
                    at: child, to: result, deltaTime: step.deltaTime, depth: step.depth + 1
                )
            }
            return result
        case let driven as HKBEventDrivenModifier:
            return applyEventDriven(
                driven, at: target, to: pose, deltaTime: step.deltaTime, depth: step.depth
            )
        case let timer as HKBTimerModifier:
            applyTimer(
                at: target, alarm: step.bound.float("alarmTimeSeconds", or: timer.alarmTimeSeconds),
                event: timer.alarmEvent, repeating: false, deltaTime: step.deltaTime
            )
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
            return runVariableModifier(object, step, to: pose)
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

    /// `hkbTimerModifier` and `BSTimerModifier`: raises `event` once `alarm`
    /// seconds have passed since activation. A repeating timer starts again each
    /// time it fires; the other stays quiet until it is reactivated.
    func applyTimer(
        at target: HKXPointerTarget,
        alarm: Float,
        event: HKBEventProperty,
        repeating: Bool,
        deltaTime: Float
    ) {
        var state = markReached(target)
        state.elapsed += deltaTime
        if !state.hasFiredAlarm, state.elapsed >= alarm {
            state.hasFiredAlarm = !repeating
            state.elapsed = repeating && alarm > 0 ? state.elapsed - alarm : state.elapsed
            raise(event)
        }
        nodeStates[target] = state
    }

    /// `BSEventEveryNEventsModifier`: counts occurrences of `m_eventToCheckFor`
    /// and raises `m_eventToSend` every N of them. With `m_randomizeNumberOfEvents`,
    /// each N is drawn from the minimum to the maximum with the instance's seeded source.
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
        if state.eventThreshold == 0 {
            state.eventThreshold = nextThreshold(of: counter)
        }
        state.eventCount += occurrences
        while state.eventCount >= state.eventThreshold {
            state.eventCount -= state.eventThreshold
            state.eventThreshold = nextThreshold(of: counter)
            raise(counter.eventToSend)
        }
        nodeStates[target] = state
    }

    private func nextThreshold(of counter: BSEventEveryNEventsModifier) -> Int {
        let maximum = max(counter.numberOfEventsBeforeSend, 1)
        guard counter.randomizeNumberOfEvents else { return maximum }
        let minimum = min(max(counter.minimumNumberOfEventsBeforeSend, 1), maximum)
        return random.next(in: minimum ... maximum)
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
        if noteModifierDeactivation(of: object, at: target) {
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
