// Bleedout: an essential actor whose health share falls to its class's bleedout ratio
// kneels instead of dying. It stands once its health is back above the ratio, or with
// full health after `fEssentialDeathTime`.
// Sources: UESP "Skyrim:Essential NPCs" and "Skyrim:Protected NPCs", and the Creation
// Kit wiki "Class". See docs/engine/ragdoll.md#bleedout.

import OpenSkyCombatInterface
public import OpenSkyFormatsESM

/// The actors in bleedout and how long each has knelt.
nonisolated struct BleedoutTracker: Equatable, Sendable {
    private(set) var seconds: [ReferenceKey: Float] = [:]

    func contains(_ key: ReferenceKey) -> Bool {
        seconds[key] != nil
    }

    /// False when the actor already bleeds out.
    mutating func enter(_ key: ReferenceKey) -> Bool {
        guard seconds[key] == nil else { return false }
        seconds[key] = 0
        return true
    }

    mutating func remove(_ key: ReferenceKey) {
        seconds[key] = nil
    }

    /// Ages every actor and returns, in key order, those who stand up. They leave the
    /// tracker. A `held` actor keeps kneeling. `recovered` says whose health is back
    /// above its kneel ratio by `fBleedoutRecover`; it counts after `fBleedoutMin`.
    mutating func advance(
        by delta: Float, settings: DeathSettings, held: (ReferenceKey) -> Bool = { _ in false },
        recovered healthBack: (ReferenceKey) -> Bool = { _ in false }
    ) -> [ReferenceKey] {
        let step = delta.isFinite ? max(delta, 0) : 0
        var recovered: [ReferenceKey] = []
        for key in seconds.keys.sorted() {
            let knelt = (seconds[key] ?? 0) + step
            let healed = knelt >= settings.bleedoutMinSeconds && healthBack(key)
            if !held(key), healed || knelt >= settings.bleedoutSeconds {
                seconds[key] = nil
                recovered.append(key)
            } else {
                seconds[key] = knelt
            }
        }
        return recovered
    }
}
