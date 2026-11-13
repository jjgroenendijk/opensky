// The helpers every evaluation part shares: typed object access, event raising,
// payloads, and the deactivation sweep.

public import OpenSkyFormatsAnimation

nonisolated extension BehaviorGraphInstance {
    /// The decoded object at `target` as `Value`, or nil.
    public func object<Value: HKBClass>(at target: HKXPointerTarget, as _: Value.Type) -> Value? {
        object(at: target) as? Value
    }
}

nonisolated extension BehaviorGraphInstance {
    /// The string an event payload carries, if it carries one.
    func payload(at target: HKXPointerTarget?) -> String? {
        guard let target else { return nil }
        return object(at: target, as: HKBStringEventPayload.self)?.data
    }
}

nonisolated extension BehaviorGraphInstance {
    /// Raises one `hkbEventProperty`, payload included. An id of -1 is Havok's
    /// "no event" and is dropped by the queue.
    func raise(_ event: HKBEventProperty) {
        events.raise(id: event.id, payload: payload(at: event.payload))
    }
}

nonisolated extension BehaviorGraphInstance {
    /// `hkbTimerModifier` and `BSTimerModifier`: raises `event` once `alarm`
    /// seconds have passed since activation. A repeating timer starts again each
    /// time it fires; the other stays quiet until it is reactivated.
    func applyTimer(
        _ step: BehaviorModifierStep,
        alarm: Float,
        event: HKBEventProperty,
        repeating: Bool
    ) {
        let target = step.target
        var state = markReached(target)
        state.elapsed += step.deltaTime
        if !state.hasFiredAlarm, state.elapsed >= alarm {
            state.hasFiredAlarm = !repeating
            state.elapsed = repeating && alarm > 0 ? state.elapsed - alarm : state.elapsed
            raise(event)
        }
        nodeStates[target] = state
    }
}

nonisolated extension BehaviorGraphInstance {
    /// Evaluates the generator at `target`. A part that runs a child generator calls
    /// this, so the parts do not call each other in a circle.
    public func evaluateGenerator(
        at target: HKXPointerTarget?,
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        generators.evaluateGenerator(at: target, depth: depth, deltaTime: deltaTime)
    }

    /// Runs the modifier at `target` on `pose`, for a part that wraps a modifier.
    func applyModifier(
        at target: HKXPointerTarget?,
        to pose: BehaviorPose,
        deltaTime: Float,
        depth: Int = 0
    ) -> BehaviorPose {
        modifiers.applyModifier(at: target, to: pose, deltaTime: deltaTime, depth: depth)
    }
}

nonisolated extension BehaviorGraphInstance {
    /// Runs the deactivation hooks of `targets` and forgets their state.
    func deactivateNodes(_ targets: Set<HKXPointerTarget>) {
        modifiers.deactivateNodes(targets)
    }

    /// Fetches every clip the graph can reach, so the first update need not wait.
    public func prefetchReachableClips() {
        childGraphs.prefetchReachableClips()
    }
}
