// The perk entry points engine code reads, by their xEdit index. Every reader takes
// its entry point from here, so `openskycli gaps` can list the entry points the data
// uses and no code reads. A SwiftLint rule rejects a raw-value literal elsewhere.

import Foundation
import OpenSkyFormatsESM

nonisolated extension PerkEntryPoint {
    public static let calculateWeaponDamage = PerkEntryPoint(rawValue: 0)
    public static let modBuyPrices = PerkEntryPoint(rawValue: 8)
    public static let calculateCriticalChance = PerkEntryPoint(rawValue: 1)
    public static let calculateCriticalDamage = PerkEntryPoint(rawValue: 2)
    public static let modSneakAttackMult = PerkEntryPoint(rawValue: 18)
    public static let modSpellMagnitude = PerkEntryPoint(rawValue: 29)
    public static let modSpellDuration = PerkEntryPoint(rawValue: 30)
    public static let modIncomingSpellMagnitude = PerkEntryPoint(rawValue: 41)
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
    public static let modTemperingHealth = PerkEntryPoint(rawValue: 76)
    public static let filterActivation = PerkEntryPoint(rawValue: 74)
    public static let modArmorWeight = PerkEntryPoint(rawValue: 32)
    public static let modIngredientsHarvested = PerkEntryPoint(rawValue: 87)
    public static let modSpellCastingSoundEvent = PerkEntryPoint(rawValue: 55)
    public static let applySneakingSpell = PerkEntryPoint(rawValue: 69)
    public static let setBooleanGraphVariable = PerkEntryPoint(rawValue: 54)
    public static let setActivateLabel = PerkEntryPoint(rawValue: 81)
    public static let adjustBookSkillPoints = PerkEntryPoint(rawValue: 5)
    public static let modDetectionLight = PerkEntryPoint(rawValue: 47)
    public static let modDetectionMovement = PerkEntryPoint(rawValue: 48)
    public static let modDetectionSneakSkill = PerkEntryPoint(rawValue: 57)
    public static let modRecoverArrowChance = PerkEntryPoint(rawValue: 21)
    public static let modSkillUse = PerkEntryPoint(rawValue: 22)
    public static let modAttackDamage = PerkEntryPoint(rawValue: 35)
    public static let modSpellCost = PerkEntryPoint(rawValue: 38)
    public static let modPercentBlocked = PerkEntryPoint(rawValue: 39)
    public static let modSellPrices = PerkEntryPoint(rawValue: 60)
    public static let modPickpocketChance = PerkEntryPoint(rawValue: 56)
    public static let canPickpocketEquippedItem = PerkEntryPoint(rawValue: 61)
    public static let shouldApplyPlacedItem = PerkEntryPoint(rawValue: 84)
    public static let modLockpickingCrimeChance = PerkEntryPoint(rawValue: 86)
    public static let modPlayerIntimidation = PerkEntryPoint(rawValue: 43)
    public static let modBribeAmount = PerkEntryPoint(rawValue: 46)
    public static let modLockpickSweetSpot = PerkEntryPoint(rawValue: 59)
    public static let setLockpickStartingArc = PerkEntryPoint(rawValue: 63)
    public static let makeLockpicksUnbreakable = PerkEntryPoint(rawValue: 65)
    public static let modLockpickingKeyRewardChance = PerkEntryPoint(rawValue: 90)
    public static let modAlchemyEffectiveness = PerkEntryPoint(rawValue: 66)
    public static let modInitialIngredientEffectsLearned = PerkEntryPoint(rawValue: 72)
    public static let purifyAlchemyIngredients = PerkEntryPoint(rawValue: 73)
    public static let modPoisonDoseCount = PerkEntryPoint(rawValue: 83)
    public static let modPotionsCreated = PerkEntryPoint(rawValue: 89)
    public static let canDualCastSpell = PerkEntryPoint(rawValue: 75)
    public static let modWardMagickaAbsorptionPct = PerkEntryPoint(rawValue: 71)
    public static let modSoulGemRecharge = PerkEntryPoint(rawValue: 49)
    public static let modSoulPctCapturedToWeapon = PerkEntryPoint(rawValue: 78)
    public static let modEnchantmentPower = PerkEntryPoint(rawValue: 77)
    public static let modAppliedEnchantmentsAllowed = PerkEntryPoint(rawValue: 80)
    public static let modShoutOK = PerkEntryPoint(rawValue: 82)
    public static let modPlayerMagicSlowdown = PerkEntryPoint(rawValue: 70)

    /// Every entry point above. An entry point outside this set changes nothing in game.
    public static let engineRead: Set<PerkEntryPoint> = [
        calculateWeaponDamage, calculateCriticalChance, calculateCriticalDamage,
        modSneakAttackMult, modBashingDamage, modPowerAttackStamina, modPowerAttackDamage,
        modIncomingStagger, modTargetStagger, modIncomingDamage, modTargetDamageResistance,
        modShieldDeflectArrowChance, setSweepAttack, applyCombatHitSpell, applyBashingSpell,
        applyWeaponSwingSpell, modArmorRating,
        modSpellMagnitude, modSpellDuration, modIncomingSpellMagnitude,
        modBuyPrices, modSellPrices, modTemperingHealth,
        modDetectionLight, modDetectionMovement, modDetectionSneakSkill, filterActivation,
        modArmorWeight, modIngredientsHarvested, modSpellCastingSoundEvent,
        applySneakingSpell, setBooleanGraphVariable, setActivateLabel,
        adjustBookSkillPoints,
        modRecoverArrowChance, modSkillUse, modAttackDamage, modSpellCost, modPercentBlocked,
        modPlayerIntimidation,
        modBribeAmount, modLockpickSweetSpot,
        setLockpickStartingArc, makeLockpicksUnbreakable, modLockpickingKeyRewardChance,
        modAlchemyEffectiveness, modInitialIngredientEffectsLearned, purifyAlchemyIngredients,
        modPoisonDoseCount, modPotionsCreated,
        modPickpocketChance, canPickpocketEquippedItem, shouldApplyPlacedItem,
        modLockpickingCrimeChance,
        canDualCastSpell, modWardMagickaAbsorptionPct, modSoulGemRecharge,
        modSoulPctCapturedToWeapon,
        modEnchantmentPower, modAppliedEnchantmentsAllowed, modShoutOK,
        modPlayerMagicSlowdown
    ]
}
