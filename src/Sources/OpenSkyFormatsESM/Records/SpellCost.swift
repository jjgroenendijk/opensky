// Auto-calculated spell cost. One effect costs
// `base_cost * (magnitude * duration / 10) ^ 1.1`, with magnitude at least 1
// and duration 10 when 0 or concentration. Each effect is truncated before
// the sum. SPIT bit 0 selects the authored cost. Formula, sources and measured
// agreement: docs/formats/magic-records.md.

import Foundation

nonisolated public struct SpellCostResult: Equatable, Sendable {
    /// The cost the game charges: the authored SPIT value on a manual-cost
    /// record, the auto-calculated total otherwise.
    public let cost: UInt32
    /// The auto-calculated total, always computed so a manual record can be
    /// compared against what the formula would have produced.
    public let autoCalculated: Float
    /// True when the record carries `SpellFlags.manualCostCalc`.
    public let isManual: Bool
    /// Effects whose MGEF link did not resolve, and so contributed nothing.
    public let unresolvedEffects: Int
}

nonisolated public enum SpellCost: Sendable {
    /// The exponent UESP documents for the per-effect cost curve.
    public static let exponent: Float = 1.1
    /// Magnitude floor and the duration substituted for an instant effect.
    public static let minimumMagnitude: Float = 1
    public static let instantDuration: Float = 10

    /// One effect's contribution, with the documented substitutions applied.
    public static func effectCost(
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
    public static func contribution(_ effectCost: Float) -> Float {
        effectCost.rounded(.down)
    }

    /// Totals per-effect costs a caller has already computed, applying the
    /// same truncation.
    public static func total(ofEffectCosts costs: [Float]) -> Float {
        costs.reduce(0) { $0 + contribution($1) }
    }

    /// The result for a record whose per-effect contributions are already
    /// summed, honoring the manual-cost flag.
    public static func result(
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
    public static func result(
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
    public static func rounded(_ total: Float) -> UInt32 {
        let value = total.rounded()
        guard value.isFinite, value > 0 else { return 0 }
        return value >= Float(UInt32.max) ? UInt32.max : UInt32(value)
    }
}
