// The Block experience a melee blow teaches: a blocked blow and a bash. Skyrim.esm
// carries none of these settings, so each keeps the engine value the CK wiki
// "Category:Settings" lists, or UESP "Skyrim:Block" where the wiki has none.
// See docs/engine/skill-advancement.md.

import Foundation
import OpenSkyGameData

nonisolated public struct MeleeSkillUseSettings: Equatable, Sendable {
    /// `fWeaponBlockSkillUseBase` and `...Mult`: a weapon block teaches
    /// `base + mult * absorbed damage`.
    public var weaponBlockBase: Float = 0
    public var weaponBlockMult: Float = 1
    /// `fBlockSkillUseMult`, from UESP only: a shield block teaches `mult * absorbed damage`.
    public var shieldBlockMult: Float = 2
    /// `fWeaponBashSkillUseBase`, `fShieldBashSkillUseBase` and their `...Mult`: a
    /// landed bash teaches `base + mult * raw damage`.
    public var weaponBashBase: Float = 1
    public var weaponBashMult: Float = 0
    public var shieldBashBase: Float = 5
    public var shieldBashMult: Float = 0

    public static let vanilla = Self()

    public init() {}

    public func blocked(absorbed: Float, withShield: Bool) -> Float {
        withShield ? shieldBlockMult * absorbed : weaponBlockBase + weaponBlockMult * absorbed
    }

    public func bash(damage: Float, withShield: Bool) -> Float {
        withShield ? shieldBashBase + shieldBashMult * damage : weaponBashBase + weaponBashMult *
            damage
    }

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fWeaponBlockSkillUseBase", into: &settings, \.weaponBlockBase)
        store.read("fWeaponBlockSkillUseMult", into: &settings, \.weaponBlockMult)
        store.read("fBlockSkillUseMult", into: &settings, \.shieldBlockMult)
        store.read("fWeaponBashSkillUseBase", into: &settings, \.weaponBashBase)
        store.read("fWeaponBashSkillUseMult", into: &settings, \.weaponBashMult)
        store.read("fShieldBashSkillUseBase", into: &settings, \.shieldBashBase)
        store.read("fShieldBashSkillUseMult", into: &settings, \.shieldBashMult)
        return settings
    }
}
