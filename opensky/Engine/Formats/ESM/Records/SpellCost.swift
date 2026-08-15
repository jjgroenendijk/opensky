// Auto-calculated spell cost.
//
// UESP documents the rule on the SPEL and SCRL pages: a spell's cost is the
// total of its effect costs, and one effect costs
//
//   effect_base_cost * (magnitude * duration / 10) ^ 1.1
//
// with three substitutions before the arithmetic — a magnitude below 1 counts
// as 1, a duration of 0 counts as 10, and a concentration spell's duration
// counts as 10 whatever the effect says. `effect_base_cost` is the MGEF DATA
// base cost, so the calculation only works once the EFID links resolve; an
// unresolved link contributes nothing and is counted so a caller can tell a
// zero-cost spell from an unresolvable one.
//
// UESP does not say where the fractional part goes. Comparing the result
// against the cost vanilla stores in SPIT says each effect's contribution is
// truncated to whole magicka before the sum, not the sum afterwards; the
// measured agreement for each variant is in docs/formats/magic-records.md.
//
// The SPIT flag bit 0 ("Manual Cost Calc" in xEdit, "not Auto-Calculate" on
// UESP) switches a record to the authored SPIT base cost instead. Records the
// game auto-calculates still store the derived value in that same word, which
// is what the real-data gate compares against.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/SPEL", Effect/EFIT row
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SPEL
//   UESP "Skyrim Mod:Mod File Format/SCRL", same row
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas: the flag is bit 0 of the SPIT
//     flags word in both `wbRecord(SPEL, ...)` and `wbRecord(SCRL, ...)`.
// Formula and measured agreement documented in docs/formats/magic-records.md.

import Foundation

nonisolated struct SpellCostResult: Equatable {
    /// The cost the game charges: the authored SPIT value on a manual-cost
    /// record, the auto-calculated total otherwise.
    let cost: UInt32
    /// The auto-calculated total, always computed so a manual record can be
    /// compared against what the formula would have produced.
    let autoCalculated: Float
    /// True when the record carries `SpellFlags.manualCostCalc`.
    let isManual: Bool
    /// Effects whose MGEF link did not resolve, and so contributed nothing.
    let unresolvedEffects: Int
}

nonisolated enum SpellCost {
    /// The exponent UESP documents for the per-effect cost curve.
    static let exponent: Float = 1.1
    /// Magnitude floor and the duration substituted for an instant effect.
    static let minimumMagnitude: Float = 1
    static let instantDuration: Float = 10

    /// One effect's contribution, with the documented substitutions applied.
    static func effectCost(
        baseCost: Float,
        magnitude: Float,
        duration: UInt32,
        castingType: MagicEffectCastingType
    ) -> Float {
        // A concentration spell charges per second, so its cost is quoted for
        // the same ten-second window an instant effect is normalized to.
        let effectiveDuration = duration == 0 || castingType == .concentration
            ? instantDuration
            : Float(duration)
        let effectiveMagnitude = max(magnitude, minimumMagnitude)
        let scale = effectiveMagnitude * effectiveDuration / instantDuration
        guard scale > 0, baseCost > 0 else { return 0 }
        return baseCost * pow(scale, exponent)
    }

    /// What one effect adds to the total: its cost truncated to whole magicka.
    /// Truncating per effect rather than once at the end is what matches the
    /// costs vanilla stores — 89 percent of auto-calculated records against 62
    /// percent for a rounded total (docs/formats/magic-records.md).
    static func contribution(_ effectCost: Float) -> Float {
        effectCost.rounded(.down)
    }

    /// Totals per-effect costs a caller has already computed, applying the
    /// same truncation.
    static func total(ofEffectCosts costs: [Float]) -> Float {
        costs.reduce(0) { $0 + contribution($1) }
    }

    /// Totals the effect list. `baseCost` returns the MGEF base cost for one
    /// effect, or nil when the EFID link does not resolve.
    static func autoCalculated(
        effects: [MagicItemEffect],
        castingType: MagicEffectCastingType,
        baseCost: (MagicItemEffect) -> Float?
    ) -> (total: Float, unresolved: Int) {
        var total: Float = 0
        var unresolved = 0
        for effect in effects {
            guard let base = baseCost(effect) else {
                unresolved += 1
                continue
            }
            total += contribution(effectCost(
                baseCost: base,
                magnitude: effect.magnitude,
                duration: effect.duration,
                castingType: castingType
            ))
        }
        return (total, unresolved)
    }

    /// The full result for a record, honoring the manual-cost flag.
    static func result(
        data: SpellItemData?,
        effects: [MagicItemEffect],
        baseCost: (MagicItemEffect) -> Float?
    ) -> SpellCostResult {
        let calculated = autoCalculated(
            effects: effects,
            castingType: data?.castingType ?? .fireAndForget,
            baseCost: baseCost
        )
        return result(
            data: data,
            total: calculated.total,
            unresolvedEffects: calculated.unresolved
        )
    }

    /// Variant for a caller that already summed the per-effect contributions,
    /// so the effect list is not resolved twice.
    static func result(
        data: SpellItemData?,
        total: Float,
        unresolvedEffects: Int
    ) -> SpellCostResult {
        result(
            isManual: data?.flags.contains(.manualCostCalc) ?? false,
            authoredCost: data?.baseCost ?? 0,
            total: total,
            unresolvedEffects: unresolvedEffects
        )
    }

    /// The same decision without a `SpellItemData` in hand. ENCH stores its
    /// authored cost and its manual-cost flag in ENIT rather than SPIT, and
    /// UESP documents the identical per-effect curve for both records, so the
    /// two headers meet here instead of in a second cost routine.
    static func result(
        isManual: Bool,
        authoredCost: UInt32,
        total: Float,
        unresolvedEffects: Int
    ) -> SpellCostResult {
        SpellCostResult(
            cost: isManual ? authoredCost : rounded(total),
            autoCalculated: total,
            isManual: isManual,
            unresolvedEffects: unresolvedEffects
        )
    }

    /// Nearest whole magicka point. A non-finite or negative total — only
    /// reachable from a mod-authored magnitude — clamps to zero rather than
    /// trapping on the conversion.
    static func rounded(_ total: Float) -> UInt32 {
        let value = total.rounded()
        guard value.isFinite, value > 0 else { return 0 }
        return value >= Float(UInt32.max) ? UInt32.max : UInt32(value)
    }
}
