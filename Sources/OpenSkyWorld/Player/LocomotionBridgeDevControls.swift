// The bridge's dev-control half for `World > Player & Locomotion > Dev Controls`, and
// the sneak reading the forced gait changes. Panel-driven; only `isSneakingNow` is on
// the step path.

import Foundation
import OpenSkyPhysics

nonisolated extension LocomotionBridge {
    /// Raises one event by name on every graph through the same `raise` the edges use,
    /// tallies included, and reports whether the third-person graph declares it.
    @discardableResult
    public func raiseGraphEvent(named name: String) -> Bool {
        raise(name)
        return status.raisedEvents.contains(name)
    }

    /// Empties the root-motion trace and its running totals.
    public func clearMotionTrace() {
        updateStatus { $0.clearMotionTrace() }
    }

    /// Whether the current step counts as sneaking for the graph. A forced gait
    /// wins, so the dev control raises the same `SneakStart` the key does; with
    /// nothing forced this is the sneak toggle, unchanged.
    public var isSneakingNow: Bool {
        forcedGait.map { $0 == .sneak } ?? intent.sneak
    }
}
