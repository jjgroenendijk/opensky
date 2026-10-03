// Lock rules with no state of their own: what a press on a locked target does, and
// what its prompt says. See docs/engine/locks.md.

import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyWorldInterface

/// What the activation gate does with one press.
nonisolated public enum LockGateDecision: Equatable, Sendable {
    /// Not locked: the activation goes through.
    case proceed
    /// Locked, and the player carries the key: unlock, then go through.
    case unlockWithKey(FormID)
    case refuse(ActivationRefusal)
}

nonisolated public enum LockCore {
    /// The prompt word for a locked target. English, like the other action words.
    public static let unlockLabel = "Unlock"

    public static func decide(lock: ReferenceLockState?, carriesKey: Bool) -> LockGateDecision {
        guard let lock, lock.isLocked else { return .proceed }
        if carriesKey, let key = lock.key {
            return .unlockWithKey(key)
        }
        return .refuse(.locked(level: lock.level, key: lock.key))
    }

    /// `interaction` as the HUD shows it: "Unlock Chest (Novice)" while locked.
    public static func labelled(
        _ interaction: PlacedInteraction,
        lock: ReferenceLockState?
    ) -> PlacedInteraction {
        guard let lock, lock.isLocked else { return interaction }
        return interaction.relabelled(
            unlockLabel, name: "\(interaction.name) (\(lock.difficulty.name))"
        )
    }
}
