// A spell's main effect: the one that gives its hand art, its projectile, and its
// explosion. See docs/engine/spellcasting.md#casting-cues.

import OpenSkyFormatsESM

nonisolated public enum MainMagicEffect {
    /// Flag bit 24 of an effect keeps it from being the main one.
    static let notMainFlag: UInt32 = 1 << 24

    /// The highest whole-number cost, the earlier one on a tie. `skipped` marks the
    /// effects that cannot be the main one.
    public static func index(costs: [Float], skipped: [Bool]) -> Int? {
        var best: (index: Int, cost: Int)?
        for (index, cost) in costs.enumerated() where !skipped[index] {
            let whole = cost.isFinite ? Int(max(0, cost)) : 0
            if let current = best, whole <= current.cost {
                continue
            }
            best = (index, whole)
        }
        return best?.index
    }

    /// The main one of `effects`. An unresolved effect, one with flag bit 24, and for a
    /// concentration spell one with no projectile, are skipped. The cost is the stored
    /// cost, before perks.
    public static func index(of effects: [ResolvedSpellEffect], concentration: Bool) -> Int? {
        let skipped = effects.map { effect in
            guard let data = effect.effect?.effect.data else { return true }
            return data.flags.rawValue & notMainFlag != 0
                || (concentration && data.projectile == nil)
        }
        return index(costs: effects.map(\.cost), skipped: skipped)
    }
}
