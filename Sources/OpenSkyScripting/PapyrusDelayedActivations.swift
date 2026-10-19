// The `XAPR` delay: the CK wiki "Reference" page gives it as "the number of seconds to
// wait after the parent's activation before activating this reference".

import OpenSkyFormatsESM

/// One activate child waiting for its parent's delay to run out.
nonisolated public struct DelayedActivation: Equatable, Sendable {
    public let child: ReferenceKey
    public let parent: ReferenceKey
    public var remaining: Float
}

extension PapyrusWorldStateBridge {
    /// Counts the delays down by `seconds` and activates each child whose delay ran out,
    /// with its parent as the activator. Returns the `OnActivate` events queued.
    @discardableResult
    public func advanceDelayedActivations(by seconds: Float) -> Int {
        guard !delayedActivations.isEmpty, seconds.isFinite, seconds > 0 else { return 0 }
        for index in delayedActivations.indices {
            delayedActivations[index].remaining -= seconds
        }
        let due = delayedActivations.filter { $0.remaining <= 0 }
        delayedActivations.removeAll { $0.remaining <= 0 }
        return due.reduce(0) { queued, pending in
            queued + activate(pending.child, by: pending.parent, togglesOpen: false).queuedEvents
        }
    }
}
