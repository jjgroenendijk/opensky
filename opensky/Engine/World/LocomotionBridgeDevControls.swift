// The bridge's dev-control half (issue #191): the two actions behind
// `World > Player & Locomotion > Dev Controls`, and the sneak reading the
// forced gait changes.
//
// It is a satellite of `LocomotionBridge.swift` for the type-length cap, and
// the split falls where it does on purpose: everything here is driven by the
// panel rather than by a frame, and none of it is on the per-step path except
// `isSneakingNow`, which the step consults but does not own.

import Foundation

nonisolated extension LocomotionBridge {
    /// Raises one event on every attached graph by name, exactly as an edge
    /// would, and reports whether the third-person graph declared it.
    ///
    /// It goes through the same `raise` the edges use, so an event fired from
    /// the sidebar is indistinguishable from one the player produced —
    /// including its effect on the status tallies, which is what makes the
    /// control evidence rather than a side channel.
    @discardableResult
    func raiseGraphEvent(named name: String) -> Bool {
        raise(name)
        return status.raisedEvents.contains(name)
    }

    /// Empties the root-motion trace and its running totals.
    func clearMotionTrace() {
        updateStatus { $0.clearMotionTrace() }
    }

    /// Whether the current step counts as sneaking for the graph. A forced gait
    /// wins, so the dev control raises the same `SneakStart` the key does; with
    /// nothing forced this is the sneak toggle, unchanged.
    var isSneakingNow: Bool {
        forcedGait.map { $0 == .sneak } ?? intent.sneak
    }
}
