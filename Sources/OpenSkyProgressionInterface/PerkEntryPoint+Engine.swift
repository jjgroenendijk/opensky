// The perk entry points engine code reads, by their xEdit index. Every reader takes
// its entry point from here, so `openskycli gaps` can list the entry points the data
// uses and no code reads. A SwiftLint rule rejects a raw-value literal elsewhere.

import Foundation
import OpenSkyFormatsESM

nonisolated extension PerkEntryPoint {
    public static let modRecoverArrowChance = PerkEntryPoint(rawValue: 21)
    public static let modSkillUse = PerkEntryPoint(rawValue: 22)
    public static let modAttackDamage = PerkEntryPoint(rawValue: 35)
    public static let modSpellCost = PerkEntryPoint(rawValue: 38)
    public static let modPercentBlocked = PerkEntryPoint(rawValue: 39)
    public static let modPlayerIntimidation = PerkEntryPoint(rawValue: 43)
    public static let modBribeAmount = PerkEntryPoint(rawValue: 46)
    public static let modLockpickSweetSpot = PerkEntryPoint(rawValue: 59)
    public static let setLockpickStartingArc = PerkEntryPoint(rawValue: 63)
    public static let makeLockpicksUnbreakable = PerkEntryPoint(rawValue: 65)
    public static let modLockpickingKeyRewardChance = PerkEntryPoint(rawValue: 90)

    /// Every entry point above. An entry point outside this set changes nothing in game.
    public static let engineRead: Set<PerkEntryPoint> = [
        modRecoverArrowChance, modSkillUse, modAttackDamage, modSpellCost, modPercentBlocked,
        modPlayerIntimidation,
        modBribeAmount, modLockpickSweetSpot,
        setLockpickStartingArc, makeLockpicksUnbreakable, modLockpickingKeyRewardChance
    ]
}
