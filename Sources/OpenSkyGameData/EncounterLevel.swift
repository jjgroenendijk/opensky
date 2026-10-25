// The level a leveled list rolls against: the player level, clamped by the
// encounter zone of the place it is asked from, then scaled by a placed leveled
// actor's difficulty (<https://ck.uesp.net/wiki/Encounter_Zone>,
// <https://ck.uesp.net/wiki/LeveledCharacter>). See docs/engine/leveled-lists.md.

import Foundation
import OpenSkyFormatsESM

/// The Leveled Actor tab's difficulty: ACHR `XLCM`, 0 easy to 3 very hard. A
/// reference without `XLCM` is `none`.
nonisolated public enum LeveledActorDifficulty: Int32, CaseIterable, Sendable {
    case easy = 0
    case medium = 1
    case hard = 2
    case veryHard = 3
    case none = 4

    public init(levelModifier: Int32?) {
        self = levelModifier.flatMap(LeveledActorDifficulty.init(rawValue:)) ?? .none
    }
}

nonisolated public enum EncounterLevel {
    /// The encounter level of a place in `zone`. No zone gives the player level.
    /// A zone raises a lower player to its minimum, unless it matches the player
    /// below it, and caps at its maximum when that is above 0.
    public static func level(
        playerLevel: Int,
        zone: EncounterZone?,
        settings: LeveledListSettings = .fallback
    ) -> Int {
        var level = max(1, playerLevel)
        if let zone {
            let minimum = Int(zone.minimumLevel ?? 0)
            let maximum = Int(zone.maximumLevel ?? 0)
            if level < minimum, !zone.flags.contains(.matchesPlayerBelowMinimumLevel) {
                level = minimum
            }
            if maximum > 0 {
                level = min(level, maximum)
            }
        }
        // No source says how the two settings apply; both are 0 in `Skyrim.esm`.
        return max(1, level + settings.calcLevelAdjustUp - settings.calcLevelAdjustDown)
    }

    /// The level a leveled actor of `difficulty` picks its list entry against.
    public static func actorListLevel(
        encounterLevel: Int,
        difficulty: LeveledActorDifficulty,
        settings: LeveledListSettings = .fallback
    ) -> Double {
        Double(encounterLevel) * settings.actorMult(difficulty) * settings.levelScalingMult
    }
}
