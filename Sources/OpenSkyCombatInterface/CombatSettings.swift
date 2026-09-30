// The GMSTs melee combat resolves its numbers from, resolved once at setup.
// Each value names its source, so a readout can tell data from a fallback. The
// install stores the block settings as fractions and differs from UESP on
// `fBlockMax` and `fBlockSkillMult`; the install wins, and every fallback is the
// observed value. See docs/engine/melee-damage.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics

nonisolated public struct CombatSettings: Equatable, Sendable {
    /// `fCombatDistance` — the base melee reach in world units, which WEAP
    /// `reach` and the actor's scale multiply. UESP "Skyrim Mod:Mod File
    /// Format/WEAP" describes DNAM `reach` as a multiplier in
    /// `fCombatDistance * NPCScale * reach`, and the same reading is what
    /// xEdit's `wbDefinitionsTES5.pas` names the field.
    public let combatDistance: MovementSetting

    /// `fBlockWeaponBase` — the fraction a weapon block starts from. 0.300 on
    /// the install; UESP writes the same term as 30 percentage points.
    public let blockWeaponBase: MovementSetting
    /// `fBlockWeaponScaling` — percentage points added per point of the
    /// *attacker's* base weapon damage. 0.200.
    public let blockWeaponScaling: MovementSetting
    /// `fShieldBaseFactor` — the fraction a shield block starts from. 0.450.
    public let shieldBaseFactor: MovementSetting
    /// `fShieldScalingFactor` — percentage points added per point of the
    /// shield's base armour rating. 0.200.
    public let shieldScalingFactor: MovementSetting
    /// The Block-skill term's weight, in `(1 + skill * mult / 100)`. 2.000 on
    /// the install, where UESP's worked examples carry 1.5.
    public let blockSkillMult: MovementSetting
    /// `fBlockMax` — the cap, as a fraction. 0.700 on the install, where UESP
    /// states an 85% cap.
    public let blockMax: MovementSetting
    /// `fBlockPowerAttackMult` — what a blocked power attack multiplies the
    /// result by. 0.660, which is the one value both sources agree on.
    public let blockPowerAttackMult: MovementSetting

    /// Values for synthetic scenes and tests: the numbers the install carries,
    /// stated explicitly so a test never depends on an install being present.
    public static let synthetic = CombatSettings(
        combatDistance: MovementSetting(value: 141, source: "OpenSky synthetic"),
        blockWeaponBase: MovementSetting(value: 0.3, source: "OpenSky synthetic"),
        blockWeaponScaling: MovementSetting(value: 0.2, source: "OpenSky synthetic"),
        shieldBaseFactor: MovementSetting(value: 0.45, source: "OpenSky synthetic"),
        shieldScalingFactor: MovementSetting(value: 0.2, source: "OpenSky synthetic"),
        blockSkillMult: MovementSetting(value: 2, source: "OpenSky synthetic"),
        blockMax: MovementSetting(value: 0.7, source: "OpenSky synthetic"),
        blockPowerAttackMult: MovementSetting(value: 0.66, source: "OpenSky synthetic")
    )

    /// Reads every setting out of `store`, falling back to the value observed
    /// in vanilla `Skyrim.esm` and saying so when the load order carries none.
    public static func resolve(store: GameSettingStore) -> CombatSettings {
        CombatSettings(
            combatDistance: float("fCombatDistance", store: store, fallback: 141),
            blockWeaponBase: float("fBlockWeaponBase", store: store, fallback: 0.3),
            blockWeaponScaling: float("fBlockWeaponScaling", store: store, fallback: 0.2),
            shieldBaseFactor: float("fShieldBaseFactor", store: store, fallback: 0.45),
            shieldScalingFactor: float("fShieldScalingFactor", store: store, fallback: 0.2),
            blockSkillMult: float("fBlockSkillMult", store: store, fallback: 2),
            blockMax: float("fBlockMax", store: store, fallback: 0.7),
            blockPowerAttackMult: float("fBlockPowerAttackMult", store: store, fallback: 0.66)
        )
    }

    /// Every setting paired with its editor ID, for the CLI report and the
    /// panel readout. Ordered as the formulas use them.
    public var report: [(editorID: String, setting: MovementSetting)] {
        [
            ("fCombatDistance", combatDistance),
            ("fBlockWeaponBase", blockWeaponBase),
            ("fBlockWeaponScaling", blockWeaponScaling),
            ("fShieldBaseFactor", shieldBaseFactor),
            ("fShieldScalingFactor", shieldScalingFactor),
            ("fBlockSkillMult", blockSkillMult),
            ("fBlockMax", blockMax),
            ("fBlockPowerAttackMult", blockPowerAttackMult)
        ]
    }

    private static func float(
        _ editorID: String,
        store: GameSettingStore,
        fallback: Float
    ) -> MovementSetting {
        guard
            let resolved = store.setting(editorID: editorID),
            case let .float(value) = resolved.setting.value,
            value.isFinite
        else {
            return MovementSetting(value: fallback, source: "vanilla Skyrim.esm value")
        }
        return MovementSetting(value: value, source: resolved.sourcePlugin)
    }
}
