// Modifier evaluation: the routing, the list and event modifiers, and deactivation.
// The variable modifiers are in `BehaviorVariableModifiers.swift`, the bone modifiers
// in `BehaviorBoneModifiers.swift` and `BehaviorAimModifiers.swift`. A class with no
// semantics passes the pose through with a `BehaviorTally.passthroughModifiers` entry.

import Foundation
import OpenSkyFormatsAnimation

nonisolated extension BehaviorGraphInstance.Modifiers {
    /// Runs the modifier at `target` over `pose`. Modifiers that only touch
    /// variables and events return the pose unchanged, which is not a
    /// pass-through and is not tallied as one.
    func applyModifier(
        at target: HKXPointerTarget?,
        to pose: BehaviorPose,
        deltaTime: Float,
        depth: Int = 0
    ) -> BehaviorPose {
        guard let target, depth < BehaviorGraphInstance.maximumDepth else {
            if target != nil {
                graph.tally.note(.depthCapReached)
            }
            return pose
        }
        guard let node = graph.compiledNode(at: target) else { return pose }
        graph.markReached(target)
        graph.tally.noteModifier()
        let bound = graph.boundValues(of: node)
        guard bound.bool("enable", or: isEnabled(node.object)), !graph.isDisabled(node) else {
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
            return applyEventDriven(driven, step, to: pose)
        case let timer as HKBTimerModifier:
            graph.applyTimer(
                step, alarm: step.bound.float("alarmTimeSeconds", or: timer.alarmTimeSeconds),
                event: timer.alarmEvent, repeating: false
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
            graph.physics.poweredRagdollControls = powered
            return pose
        case let listener as BSRagdollContactListenerModifier:
            let id = listener.contactEvent.id
            graph.physics.ragdollContactEvent = graph.events.names.indices.contains(id) ? graph
                .events
                .names[id] : nil
            return pose
        default:
            return graph.variableModifiers.runVariableModifier(object, step, to: pose)
        }
    }

    // MARK: - Implemented modifiers

    /// `hkbEventDrivenModifier`: runs its wrapped modifier only while active.
    /// `m_activateEventId` starts it, `m_deactivateEventId` stops it, and
    /// `m_activeByDefault` sets the state it starts in.
    private func applyEventDriven(
        _ driven: HKBEventDrivenModifier,
        _ step: BehaviorModifierStep,
        to pose: BehaviorPose
    ) -> BehaviorPose {
        let (target, deltaTime, depth) = (step.target, step.deltaTime, step.depth)
        var state = graph.markReached(target)
        if !state.hasSeeded {
            state.hasSeeded = true
            state.isModifierRunning = driven.activeByDefault
        }
        if graph.events.isActive(id: driven.activateEventId) {
            state.isModifierRunning = true
        }
        if graph.events.isActive(id: driven.deactivateEventId) {
            state.isModifierRunning = false
        }
        graph.nodeStates[target] = state
        guard state.isModifierRunning else { return pose }
        return applyModifier(
            at: driven.wrapped, to: pose, deltaTime: deltaTime, depth: depth + 1
        )
    }

    /// `BSEventEveryNEventsModifier`: counts occurrences of `m_eventToCheckFor`
    /// and raises `m_eventToSend` every N of them. With `m_randomizeNumberOfEvents`,
    /// each N is drawn from the minimum to the maximum with the instance's seeded source.
    private func applyEventCounter(
        _ counter: BSEventEveryNEventsModifier,
        at target: HKXPointerTarget
    ) {
        var state = graph.markReached(target)
        let occurrences = graph.events.active.count { $0.id == counter.eventToCheckFor.id }
        guard occurrences > 0 else {
            graph.nodeStates[target] = state
            return
        }
        if state.eventThreshold == 0 {
            state.eventThreshold = nextThreshold(of: counter)
        }
        state.eventCount += occurrences
        while state.eventCount >= state.eventThreshold {
            state.eventCount -= state.eventThreshold
            state.eventThreshold = nextThreshold(of: counter)
            graph.raise(counter.eventToSend)
        }
        graph.nodeStates[target] = state
    }

    private func nextThreshold(of counter: BSEventEveryNEventsModifier) -> Int {
        let maximum = max(counter.numberOfEventsBeforeSend, 1)
        guard counter.randomizeNumberOfEvents else { return maximum }
        let minimum = min(max(counter.minimumNumberOfEventsBeforeSend, 1), maximum)
        return graph.nodeMemory.random.next(in: minimum ... maximum)
    }

    /// `hkbRigidBodyRagdollControlsModifier`: publishes the authored blend duration so
    /// `RagdollRuntime` uses it. `m_bones` is not read; the ragdoll uses every body in
    /// the skeleton NIF.
    private func applyRagdollControls(_ controls: HKBRigidBodyRagdollControlsModifier) {
        graph.physics.ragdollBlendDuration = controls.durationToBlend
    }

    // MARK: - Deactivation
}

nonisolated extension BehaviorGraphInstance.Modifiers {
    /// Runs the deactivation hooks of `targets` and forgets their state.
    func deactivateNodes(_ targets: Set<HKXPointerTarget>) {
        for target in targets.sorted(by: BehaviorGraphInstance.isOrderedBefore) {
            if let object = graph.object(at: target) {
                noteDeactivation(of: object, at: target)
            }
            graph.nodeStates[target] = nil
        }
        graph.reachedThisUpdate.subtract(targets)
    }

    /// Runs a node's deactivation: `BSEventOnDeactivateModifier` raises its event, and
    /// `hkbStateMachine` leaves its state, and a behavior reference stops its graph.
    func noteDeactivation(of object: any HKBClass, at target: HKXPointerTarget) {
        if let machine = object as? HKBStateMachine {
            graph.stateMachines.noteMachineDeactivation(of: machine, at: target)
            return
        }
        if let reference = object as? HKBBehaviorReferenceGenerator {
            graph.childGraphs.noteReferenceDeactivation(reference)
            return
        }
        if graph.variableModifiers.noteModifierDeactivation(of: object, at: target) {
            return
        }
        guard
            let modifier = object as? BSEventOnDeactivateModifier,
            modifier.modifier.enable
        else {
            return
        }
        graph.events.raise(
            id: modifier.event.id,
            payload: graph.payload(at: modifier.event.payload)
        )
    }
}
