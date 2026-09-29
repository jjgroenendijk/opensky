// The fortify multipliers of the melee, archery, and block formulas. Each action
// adds an enchantment value and a potion value, because a worn item moves the
// first and a potion the second. Magnitudes are percentage points.
// Documented in docs/engine/item-enchantments.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM

/// The fortify multipliers the damage formulas take.
///
/// Pure arithmetic over a value reader, with no store and no world, so every
/// number below is a plain assertion in a test rather than something only a running
/// session can show.
nonisolated public enum CombatFortifyBonus: Sendable {
    /// Percentage points per unit of multiplier.
    public static let pointsPerWhole: Float = 100

    /// One-Handed Modifier and One-Handed Power Modifier.
    public static let oneHandedIndices = indices("One-Handed Modifier", "One-Handed Power Modifier")
    /// Two-Handed Modifier and Two-Handed Power Modifier.
    public static let twoHandedIndices = indices("Two-Handed Modifier", "Two-Handed Power Modifier")
    /// Marksman Modifier and Marksman Power Modifier, which is what a bow reads.
    public static let archeryIndices = indices("Marksman Modifier", "Marksman Power Modifier")
    /// Block Modifier and Block Power Modifier.
    public static let blockIndices = indices("Block Modifier", "Block Power Modifier")

    /// The multiplier a melee swing with `handType` earns.
    ///
    /// Which pair is read follows the animation family the weapon belongs to,
    /// because that is the only thing this engine knows about a swing that
    /// distinguishes one-handed from two-handed. An empty hand reads neither: an
    /// unarmed hit is neither a one-handed nor a two-handed attack.
    public static func melee(handType: CombatHandType, reading value: (Int32) -> Float?) -> Float {
        switch handType {
        case .sword, .dagger, .axe, .mace: multiplier(of: oneHandedIndices, reading: value)
        case .greatsword, .battleaxe: multiplier(of: twoHandedIndices, reading: value)
        case .bow, .crossbow: multiplier(of: archeryIndices, reading: value)
        default: 1
        }
    }

    /// The multiplier a bow shot earns.
    public static func archery(reading value: (Int32) -> Float?) -> Float {
        multiplier(of: archeryIndices, reading: value)
    }

    /// The multiplier a block earns, which multiplies the blocked fraction.
    public static func block(reading value: (Int32) -> Float?) -> Float {
        multiplier(of: blockIndices, reading: value)
    }

    /// `1 + points / 100`, summing every index and floored at zero.
    ///
    /// Floored rather than allowed negative because the formulas it feeds treat
    /// their bonus as a non-negative multiplier: a detrimental effect big enough to
    /// take the sum below -100 points would otherwise turn a hit into a heal.
    public static func multiplier(of indices: [Int32], reading value: (Int32) -> Float?) -> Float {
        let points = indices.reduce(into: Float(0)) { total, index in
            guard let read = value(index), read.isFinite else { return }
            total += read
        }
        return max(0, 1 + points / pointsPerWhole)
    }

    /// The vanilla indices `names` spell, dropping any the table does not name so
    /// a renamed value is a missing term rather than a crash.
    private static func indices(_ names: String...) -> [Int32] {
        names.compactMap { ActorValueIdentity.index(named: $0) }
    }
}
