// What an enchanted weapon spends per hit. Full charge is the weapon's `EAMT`, one
// use costs the enchantment's cost, and the cost is not scaled by skill, because
// no source gives that formula. Documented in docs/engine/item-enchantments.md.

import Foundation

/// One enchanted weapon's charge, as a value a readout can print and a test can
/// assert on.
///
/// A value type with no store behind it, so the arithmetic is checkable without
/// a world: `EnchantmentRuntime` is what reads and writes the stored number.
nonisolated public struct EnchantmentCharge: Equatable, Sendable {
    /// The weapon's `EAMT`: the fully charged value.
    public let capacity: Float
    /// What is left of it.
    public let remaining: Float
    /// What one hit spends — the enchantment's cost. Zero for an enchantment
    /// that charges nothing, which then fires forever.
    public let costPerUse: Float

    public init(capacity: Float, remaining: Float, costPerUse: Float) {
        self.capacity = Self.clamped(capacity)
        self.remaining = min(Self.clamped(remaining), self.capacity)
        self.costPerUse = Self.clamped(costPerUse)
    }

    /// A fully charged weapon.
    public init(capacity: Float, costPerUse: Float) {
        self.init(capacity: capacity, remaining: capacity, costPerUse: costPerUse)
    }

    /// Whether the enchantment spends anything at all. False for a cost of
    /// zero and for a weapon whose record names no charge, both of which fire
    /// without ever running down.
    public var isMetered: Bool {
        costPerUse > 0 && capacity > 0
    }

    /// How many more hits the enchantment can pay for. `Int.max` when nothing
    /// is metered, which is the honest answer to "how many uses does a
    /// cost-free enchantment have".
    public var usesRemaining: Int {
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
    public var canFire: Bool {
        !isMetered || remaining >= costPerUse
    }

    /// Fraction of the full charge still held, `0...1`. Zero when the weapon
    /// carries no charge field at all.
    public var fraction: Float {
        guard capacity > 0 else { return 0 }
        return min(max(0, remaining / capacity), 1)
    }

    /// This charge after one hit paid for itself, or nil when it could not.
    public func spending() -> EnchantmentCharge? {
        guard canFire else { return nil }
        guard isMetered else { return self }
        return EnchantmentCharge(
            capacity: capacity,
            remaining: remaining - costPerUse,
            costPerUse: costPerUse
        )
    }

    /// This charge with `amount` put back, capped at the capacity.
    public func restoring(to amount: Float) -> EnchantmentCharge {
        EnchantmentCharge(capacity: capacity, remaining: amount, costPerUse: costPerUse)
    }

    /// One line for a readout: what is left, out of what, and how many hits
    /// that buys.
    public var describedLine: String {
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
