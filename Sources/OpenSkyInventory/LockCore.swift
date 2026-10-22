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
        lock: ReferenceLockState?,
        texts: LockTexts = .vanilla,
        noviceMaximum: UInt8 = 1
    ) -> PlacedInteraction {
        guard let lock, lock.isLocked else { return interaction }
        let band = lock.difficulty(noviceMaximum: noviceMaximum)
        return interaction.relabelled(
            texts.unlock, name: "\(interaction.name) (\(texts.name(of: band)))"
        )
    }

    /// The level a leveled lock shows (`XLOC` flag 0x04). CK wiki "Reference": it has its
    /// authored level at player level 1 and gets harder as the player levels. The step,
    /// one band per `playerLevelsPerBand` levels up to Master, is OpenSky's choice.
    public static func leveledLevel(
        authored: UInt8, playerLevel: Int, playerLevelsPerBand: Int = 10
    ) -> UInt8 {
        let band = LockDifficulty(level: authored)
        guard band.isPickable, playerLevelsPerBand > 0 else { return authored }
        let steps = max(0, playerLevel - 1) / playerLevelsPerBand
        let raised = min(band.rawValue + steps, LockDifficulty.master.rawValue)
        guard raised > band.rawValue, let shown = LockDifficulty(rawValue: raised) else {
            return authored
        }
        return shown.authoredLevel
    }

    /// Why a press the gate refused cannot become a picking session, or nil when
    /// the minigame opens.
    public static func refusalNotice(for band: LockDifficulty, lockpicks: Int32) -> LockNotice? {
        if !band.isPickable {
            return .requiresKey
        }
        return lockpicks > 0 ? nil : .outOfLockpicks
    }
}
