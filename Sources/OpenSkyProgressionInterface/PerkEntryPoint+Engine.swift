// The perk entry points engine code reads, by their xEdit index. Every reader takes
// its entry point from here, so `openskycli gaps` can list the entry points the data
// uses and no code reads. A SwiftLint rule rejects a raw-value literal elsewhere.

import Foundation
import OpenSkyFormatsESM

nonisolated extension PerkEntryPoint {
    public static let calculateWeaponDamage = PerkEntryPoint(rawValue: 0)
    public static let calculateCriticalChance = PerkEntryPoint(rawValue: 1)
    public static let calculateCriticalDamage = PerkEntryPoint(rawValue: 2)
    public static let modSneakAttackMult = PerkEntryPoint(rawValue: 18)
    public static let modBashingDamage = PerkEntryPoint(rawValue: 26)
    public static let modPowerAttackStamina = PerkEntryPoint(rawValue: 27)
    public static let modPowerAttackDamage = PerkEntryPoint(rawValue: 28)
    public static let modIncomingStagger = PerkEntryPoint(rawValue: 33)
    public static let modTargetStagger = PerkEntryPoint(rawValue: 34)
    public static let modIncomingDamage = PerkEntryPoint(rawValue: 36)
    public static let modTargetDamageResistance = PerkEntryPoint(rawValue: 37)
    public static let modShieldDeflectArrowChance = PerkEntryPoint(rawValue: 40)
    public static let setSweepAttack = PerkEntryPoint(rawValue: 50)
    public static let applyCombatHitSpell = PerkEntryPoint(rawValue: 51)
    public static let applyBashingSpell = PerkEntryPoint(rawValue: 52)
    public static let applyWeaponSwingSpell = PerkEntryPoint(rawValue: 67)
    public static let modArmorRating = PerkEntryPoint(rawValue: 85)
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
        calculateWeaponDamage, calculateCriticalChance, calculateCriticalDamage,
        modSneakAttackMult, modBashingDamage, modPowerAttackStamina, modPowerAttackDamage,
        modIncomingStagger, modTargetStagger, modIncomingDamage, modTargetDamageResistance,
        modShieldDeflectArrowChance, setSweepAttack, applyCombatHitSpell, applyBashingSpell,
        applyWeaponSwingSpell, modArmorRating,
        modRecoverArrowChance, modSkillUse, modAttackDamage, modSpellCost, modPercentBlocked,
        modPlayerIntimidation,
        modBribeAmount, modLockpickSweetSpot,
        setLockpickStartingArc, makeLockpicksUnbreakable, modLockpickingKeyRewardChance
    ]
}
