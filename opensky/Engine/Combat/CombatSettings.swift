// The GMSTs melee combat resolves its numbers from (issue #195, roadmap item
// 15.4), in the shape `PlayerMovementConfiguration` already established:
// immutable, resolved once at setup, every value carrying the name of where it
// came from so a readout can say "this is Skyrim.esm's number" rather than
// presenting a fallback as the same kind of fact.
//
// Resolved once rather than looked up per swing for the same reason the
// controller tuning is: a fixed-step simulation that reaches back into game
// data mid-step is a simulation whose result depends on when it was asked.
//
// Provenance for every constant is recorded on the field that uses it, and one
// thing has to be said up front because it contradicts the secondary source.
//
// UESP "Skyrim:Block" writes both block formulas in percentage points — a base
// of 30 for a weapon, 45 for a shield, a cap of 85, and a skill weight of 1.5.
// Reading `Skyrim.esm` on the local install (2026-08-07, `openskycli gmst
// combat`) gives the same settings as **fractions**, and two of them with
// different values:
//
//     fCombatDistance       141.000   fBlockWeaponBase       0.300
//     fBlockWeaponScaling     0.200   fShieldBaseFactor      0.450
//     fShieldScalingFactor    0.200   fBlockSkillMult        2.000
//     fBlockMax               0.700   fBlockPowerAttackMult  0.660
//
// So `fBlockWeaponBase` is 0.3 where UESP says 30, `fBlockMax` is 0.70 where
// UESP says 85%, and `fBlockSkillMult` is 2.0 where UESP's formula carries 1.5.
// The install wins: these are the numbers the shipped game reads. What UESP
// still supplies, and what the raw values cannot, is the *shape* — which term
// multiplies which — and that shape reconciles with the fractions on exactly
// one reading, the one `MeleeDamage` implements: the two base terms and the cap
// are fractions of the incoming damage, and the two scaling terms are
// percentage points per unit of damage or armour, so they carry a `/ 100`.
//
// Every fallback below is therefore the value observed on the install rather
// than the value UESP prints, and says so in its source string.
//
// Documented in docs/engine/melee-combat.md.

import Foundation

nonisolated struct CombatSettings: Equatable {
    /// `fCombatDistance` — the base melee reach in world units, which WEAP
    /// `reach` and the actor's scale multiply. UESP "Skyrim Mod:Mod File
    /// Format/WEAP" describes DNAM `reach` as a multiplier in
    /// `fCombatDistance * NPCScale * reach`, and the same reading is what
    /// xEdit's `wbDefinitionsTES5.pas` names the field.
    let combatDistance: MovementSetting

    /// `fBlockWeaponBase` — the fraction a weapon block starts from. 0.300 on
    /// the install; UESP writes the same term as 30 percentage points.
    let blockWeaponBase: MovementSetting
    /// `fBlockWeaponScaling` — percentage points added per point of the
    /// *attacker's* base weapon damage. 0.200.
    let blockWeaponScaling: MovementSetting
    /// `fShieldBaseFactor` — the fraction a shield block starts from. 0.450.
    let shieldBaseFactor: MovementSetting
    /// `fShieldScalingFactor` — percentage points added per point of the
    /// shield's base armour rating. 0.200.
    let shieldScalingFactor: MovementSetting
    /// The Block-skill term's weight, in `(1 + skill * mult / 100)`. 2.000 on
    /// the install, where UESP's worked examples carry 1.5.
    let blockSkillMult: MovementSetting
    /// `fBlockMax` — the cap, as a fraction. 0.700 on the install, where UESP
    /// states an 85% cap.
    let blockMax: MovementSetting
    /// `fBlockPowerAttackMult` — what a blocked power attack multiplies the
    /// result by. 0.660, which is the one value both sources agree on.
    let blockPowerAttackMult: MovementSetting

    /// Values for synthetic scenes and tests: the numbers the install carries,
    /// stated explicitly so a test never depends on an install being present.
    static let synthetic = CombatSettings(
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
    static func resolve(store: GameSettingStore) -> CombatSettings {
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
    var report: [(editorID: String, setting: MovementSetting)] {
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
