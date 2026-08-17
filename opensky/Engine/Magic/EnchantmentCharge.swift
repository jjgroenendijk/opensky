// What an enchanted weapon spends when it lands a hit (issue #472, roadmap item
// 19.9): where the charge comes from, what one use costs, and when the
// enchantment stops firing.
//
// ## The model, and how it was settled
//
// Two numbers, both already decoded, and no formula invented here:
//
// * The fully charged value is the weapon's own `EAMT`, which
//   `ItemEnchantment.charge` carries. ARMO has no such field, which is
//   consistent with an armour enchantment being a constant effect that spends
//   nothing (<https://ck.uesp.net/wiki/Enchantment>: "Armor Enchantments must
//   use the 'Constant Effect' casting type").
// * One use costs the enchantment's own cost — `ENIT`'s authored value under the
//   manual-cost flag and `SpellCost`'s auto-calculated total otherwise, which is
//   exactly what `ResolvedEnchantment.cost` already resolves.
//
// So the number of uses is `floor(EAMT / cost)`, and that was *measured* rather
// than assumed. UESP's "Skyrim:Generic Magic Weapons" prints a "Charge/Cost =
// Uses" column for every randomly generated magic weapon
// (<https://en.uesp.net/wiki/Skyrim:Generic_Magic_Weapons>), stating that its
// numbers are "base values, equivalent to the values for a player with 0 in all
// skills". Five of its rows were checked against this machine's install on
// 2026-08-17 and every one agreed on all three numbers:
//
//   Dwarven Warhammer of Absorption   1000 / 18  = 55
//   Ebony Battleaxe of the Vampire    3000 / 109 = 27
//   Iron Battleaxe of Dismay           500 / 7   = 71
//   Imperial Bow of Cowardice          300 / 11  = 27
//   Elven Battleaxe of Banishing      2000 / 138 = 14
//
// The measurement is in `EnchantmentRuntimeRealDataTests`, so the agreement is a
// gate rather than a comment.
//
// ## What is deliberately not modelled
//
// The cost is *not* scaled by the wielder's skill. UESP states plainly that the
// uses go up with "a relevant magic skill" and that at skill 100 a weapon gets
// "about 1.7 times the uses documented here", and the same page's charge-per-use
// formula for a *player-created* enchantment carries an Enchanting-skill term.
// Neither statement pins the runtime multiplier: the two disagree about which
// skill is read, and 1.7 is quoted as an approximation with no formula beside it.
// Rather than invent one, this engine charges the base cost, which is the number
// the published tables print, and records the gap in docs/engine/magic.md.
//
// Recharging is out of this item's scope: an empty weapon stays empty, because
// soul gems are not in this milestone. `restoring(to:)` exists for the load path
// and for a dev control, not for a soul gem.
//
// Documented in docs/engine/magic.md.

import Foundation

/// One enchanted weapon's charge, as a value a readout can print and a test can
/// assert on.
///
/// A value type with no store behind it, so the arithmetic is checkable without
/// a world: `EnchantmentRuntime` is what reads and writes the stored number.
nonisolated struct EnchantmentCharge: Equatable, Sendable {
    /// The weapon's `EAMT`: the fully charged value.
    let capacity: Float
    /// What is left of it.
    let remaining: Float
    /// What one hit spends — the enchantment's cost. Zero for an enchantment
    /// that charges nothing, which then fires forever.
    let costPerUse: Float

    init(capacity: Float, remaining: Float, costPerUse: Float) {
        self.capacity = Self.clamped(capacity)
        self.remaining = min(Self.clamped(remaining), self.capacity)
        self.costPerUse = Self.clamped(costPerUse)
    }

    /// A fully charged weapon.
    init(capacity: Float, costPerUse: Float) {
        self.init(capacity: capacity, remaining: capacity, costPerUse: costPerUse)
    }

    /// Whether the enchantment spends anything at all. False for a cost of
    /// zero and for a weapon whose record names no charge, both of which fire
    /// without ever running down.
    var isMetered: Bool {
        costPerUse > 0 && capacity > 0
    }

    /// How many more hits the enchantment can pay for. `Int.max` when nothing
    /// is metered, which is the honest answer to "how many uses does a
    /// cost-free enchantment have".
    var usesRemaining: Int {
        guard isMetered else { return .max }
        return Int((remaining / costPerUse).rounded(.down))
    }

    /// Whether the next hit can pay for itself.
    ///
    /// A weapon holding less than one whole use cannot fire: vanilla's own
    /// enchanting menu refuses a soul gem too small to buy "at least one
    /// charge" (<https://en.uesp.net/wiki/Skyrim:Enchanting>), so a fraction of
    /// a use is not a use. The leftover is stranded rather than spent, which is
    /// also why `usesRemaining` floors.
    var canFire: Bool {
        !isMetered || remaining >= costPerUse
    }

    /// Fraction of the full charge still held, `0...1`. Zero when the weapon
    /// carries no charge field at all.
    var fraction: Float {
        guard capacity > 0 else { return 0 }
        return min(max(0, remaining / capacity), 1)
    }

    /// This charge after one hit paid for itself, or nil when it could not.
    func spending() -> EnchantmentCharge? {
        guard canFire else { return nil }
        guard isMetered else { return self }
        return EnchantmentCharge(
            capacity: capacity,
            remaining: remaining - costPerUse,
            costPerUse: costPerUse
        )
    }

    /// This charge with `amount` put back, capped at the capacity.
    func restoring(to amount: Float) -> EnchantmentCharge {
        EnchantmentCharge(capacity: capacity, remaining: amount, costPerUse: costPerUse)
    }

    /// One line for a readout: what is left, out of what, and how many hits
    /// that buys.
    var describedLine: String {
        guard isMetered else {
            return capacity > 0 ? String(format: "%.0f charge, unmetered", capacity) : "no charge"
        }
        return String(
            format: "%.0f/%.0f charge, %d use(s) left", remaining, capacity, usesRemaining
        )
    }

    private static func clamped(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }
}
