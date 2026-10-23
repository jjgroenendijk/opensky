// Bleedout: an essential actor whose health share falls to its class's bleedout ratio
// kneels instead of dying, and stands up with full health after `fEssentialDeathTime`.
// Sources: UESP "Skyrim:Essential NPCs" and "Skyrim:Protected NPCs", and the Creation
// Kit wiki "Class". See docs/engine/ragdoll.md#bleedout.

import OpenSkyFormatsESM

/// What zero health does to one actor.
nonisolated public enum ZeroHealthOutcome: Equatable, Sendable {
    case dies
    /// `StartDeferredKill` holds the death until `EndDeferredKill`.
    case deferred
    case bleedsOut
}

/// The actors in bleedout and how long each has knelt.
nonisolated public struct BleedoutTracker: Equatable, Sendable {
    public private(set) var seconds: [ReferenceKey: Float] = [:]

    public init() {}

    public func contains(_ key: ReferenceKey) -> Bool {
        seconds[key] != nil
    }

    /// False when the actor already bleeds out.
    public mutating func enter(_ key: ReferenceKey) -> Bool {
        guard seconds[key] == nil else { return false }
        seconds[key] = 0
        return true
    }

    public mutating func remove(_ key: ReferenceKey) {
        seconds[key] = nil
    }

    /// Ages every actor and returns, in key order, those whose time is up. They leave
    /// the tracker. A `held` actor keeps kneeling.
    public mutating func advance(
        by delta: Float, settings: DeathSettings, held: (ReferenceKey) -> Bool = { _ in false }
    ) -> [ReferenceKey] {
        let step = delta.isFinite ? max(delta, 0) : 0
        var recovered: [ReferenceKey] = []
        for key in seconds.keys.sorted() {
            let knelt = (seconds[key] ?? 0) + step
            if !held(key), knelt >= settings.bleedoutSeconds {
                seconds[key] = nil
                recovered.append(key)
            } else {
                seconds[key] = knelt
            }
        }
        return recovered
    }
}
