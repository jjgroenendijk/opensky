// What sprinting and blocking take from stamina. The values are the install's;
// see docs/engine/actor-value-store.md, "Stamina use".

import Foundation

nonisolated public struct StaminaSettings: Equatable, Sendable {
    /// `fSprintStaminaDrainMult`: stamina a second at no worn weight.
    public var sprintDrainMult: Float = 7
    /// `fSprintStaminaWeightBase` and `fSprintStaminaWeightMult`: the drain scales by
    /// `base + wornWeight * mult`, so each unit of worn weight adds 2% (UESP "Skyrim:Stamina").
    public var sprintWeightBase: Float = 1
    public var sprintWeightMult: Float = 0.02
    /// `fStaminaBlockBase` and `fStaminaBlockDmgMult`: a blocked blow costs
    /// `base + mult * incomingDamage`.
    public var blockBase: Float = 0
    public var blockDamageMult: Float = 0.25

    public static let vanilla = Self()

    public init() {}

    /// Stamina a second of sprinting costs while wearing `wornWeight`.
    public func sprintDrain(wornWeight: Float) -> Float {
        let weight = wornWeight.isFinite ? max(0, wornWeight) : 0
        return max(0, sprintDrainMult * (sprintWeightBase + weight * sprintWeightMult))
    }

    /// Stamina a block of `incomingDamage` costs the blocker.
    public func blockCost(incomingDamage: Float) -> Float {
        let damage = incomingDamage.isFinite ? max(0, incomingDamage) : 0
        return max(0, blockBase + blockDamageMult * damage)
    }

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fSprintStaminaDrainMult", into: &settings, \.sprintDrainMult)
        store.read("fSprintStaminaWeightBase", into: &settings, \.sprintWeightBase)
        store.read("fSprintStaminaWeightMult", into: &settings, \.sprintWeightMult)
        store.read("fStaminaBlockBase", into: &settings, \.blockBase)
        store.read("fStaminaBlockDmgMult", into: &settings, \.blockDamageMult)
        return settings
    }
}
