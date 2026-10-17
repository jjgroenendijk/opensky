// Power attacks and bashes: their damage, stamina, and reach. Settings that
// Skyrim.esm does not carry keep the engine values UESP "Skyrim:Block" lists.
// See docs/engine/melee-damage.md, "Power attacks and bashes".

import Foundation
import OpenSkyGameData

nonisolated public struct PowerAttackSettings: Equatable, Sendable {
    /// `fPowerAttackDefaultBonus`: a power attack deals `1 + bonus` times the damage.
    public var damageBonus: Float = 1
    /// `fStaminaAttackWeaponBase`, `fStaminaAttackWeaponMult`, and
    /// `fPowerAttackStaminaPenalty`: the cost is `(base + weight * mult) * penalty`.
    public var staminaWeaponBase: Float = 20
    public var staminaWeaponMult: Float = 1
    public var staminaPenalty: Float = 2
    /// `fPowerAttackCoolDownTime`: seconds before the next power attack.
    public var coolDown: Float = 0
    /// `fStaminaBashBase` and `fStaminaPowerBashBase`.
    public var bashStamina: Float = 35
    public var powerBashStamina: Float = 55
    /// `fCombatBashReach`: a bash reaches this far whatever the weapon.
    public var bashReach: Float = 141
    /// `fWeaponBash*` and `fShieldBash*`: the bash factor at Block 0 and at 100.
    public var weaponBash = BashRange(playerMin: 0.1, playerMax: 0.5, min: 0.1, max: 0.25)
    public var shieldBash = BashRange(playerMin: 0.1, playerMax: 0.25, min: 0.05, max: 0.25)

    public static let vanilla = Self()
    /// UESP "Skyrim:Combat": a power bash deals three times a bash. No setting holds it.
    public static let powerBashMultiplier: Float = 3

    public init() {}

    /// Stamina a power attack with a weapon of `weight` costs.
    public func powerAttackStamina(weight: Float) -> Float {
        let load = weight.isFinite ? max(0, weight) : 0
        return max(0, (staminaWeaponBase + load * staminaWeaponMult) * staminaPenalty)
    }

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fPowerAttackDefaultBonus", into: &settings, \.damageBonus)
        store.read("fStaminaAttackWeaponBase", into: &settings, \.staminaWeaponBase)
        store.read("fStaminaAttackWeaponMult", into: &settings, \.staminaWeaponMult)
        store.read("fPowerAttackStaminaPenalty", into: &settings, \.staminaPenalty)
        store.read("fPowerAttackCoolDownTime", into: &settings, \.coolDown)
        store.read("fStaminaBashBase", into: &settings, \.bashStamina)
        store.read("fStaminaPowerBashBase", into: &settings, \.powerBashStamina)
        store.read("fCombatBashReach", into: &settings, \.bashReach)
        store.read("fWeaponBashPCMin", into: &settings, \.weaponBash.playerMin)
        store.read("fWeaponBashPCMax", into: &settings, \.weaponBash.playerMax)
        store.read("fWeaponBashMin", into: &settings, \.weaponBash.min)
        store.read("fWeaponBashMax", into: &settings, \.weaponBash.max)
        store.read("fShieldBashPCMin", into: &settings, \.shieldBash.playerMin)
        store.read("fShieldBashPCMax", into: &settings, \.shieldBash.playerMax)
        store.read("fShieldBashMin", into: &settings, \.shieldBash.min)
        store.read("fShieldBashMax", into: &settings, \.shieldBash.max)
        return settings
    }
}

/// The bash factor runs from `min` at Block 0 to `max` at 100; the player has its own pair.
nonisolated public struct BashRange: Equatable, Sendable {
    public var playerMin: Float
    public var playerMax: Float
    public var min: Float
    public var max: Float

    public init(playerMin: Float, playerMax: Float, min: Float, max: Float) {
        self.playerMin = playerMin
        self.playerMax = playerMax
        self.min = min
        self.max = max
    }

    /// The factor at `blockSkill` for the player or an NPC.
    public func factor(blockSkill: Float, isPlayer: Bool) -> Float {
        let skill = blockSkill.isFinite ? Swift.min(Swift.max(blockSkill, 0), 100) : 0
        let low = isPlayer ? playerMin : min
        let high = isPlayer ? playerMax : max
        return low + skill / 100 * (high - low)
    }
}
