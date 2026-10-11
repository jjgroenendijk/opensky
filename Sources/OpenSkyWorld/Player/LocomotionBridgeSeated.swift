// A seated player, such as a cart passenger: the graph plays the seat idle and
// nothing moves the body. See docs/engine/idle-runtime.md.

import OpenSkyBehavior

nonisolated extension LocomotionBridge {
    /// Plays an idle on the graph, as `PlayIdle` does. A seated step raises it again
    /// until the graph is in `state`; a walking step raises it once.
    public func playIdle(_ name: String, state: String?) {
        pendingIdle = (name, state)
    }

    /// A seated step runs the graph's seat state and nothing else: a seated player
    /// neither walks nor falls, so no variable or edge event goes in.
    public func advanceSeated(deltaTime: Float) {
        guard deltaTime > 0 else { return }
        if let pendingIdle {
            raise(pendingIdle.event)
        }
        _ = advanceGraph(deltaTime: deltaTime)
        if let state = pendingIdle?.state {
            let entered = graph?.activeStates.contains { $0.stateName == state } ?? true
            pendingIdle = entered ? nil : pendingIdle
        } else {
            pendingIdle = nil
        }
        wasGrounded = true
        wasMoving = false
    }
}
