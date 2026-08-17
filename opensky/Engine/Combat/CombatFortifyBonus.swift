// The fortify terms the damage formulas were built to leave open (issue #472,
// roadmap item 19.9, scope point 3).
//
// Items 15.4 and 15.5 wrote `MeleeDamage` and `ArcheryDamage` with a
// `bonusMultiplier` parameter documented as "the perk, enchantment and potion
// terms, folded into one. 1 for a character with none, which is every character in
// this milestone." This is where that number now comes from, for the enchantment
// and potion halves; perks are still M18's and still fold into the same term.
//
// ## Which actor values, measured
//
// UESP notes that "Many Fortify Skill enchantments actually affect the action
// directly instead of increasing your skill"
// (<https://en.uesp.net/wiki/Skyrim:Enchanting_Effects>), and the vanilla records
// say exactly which value each one moves. Read off this machine's install on
// 2026-08-17, every one a Peak Value Modifier with the Recover flag set:
//
//   EnchFortifyOneHandedConstantSelf -> One-Handed Modifier        (96)
//   EnchFortifyTwoHandedConstantSelf -> Two-Handed Modifier        (97)
//   EnchFortifyArcheryConstantSelf   -> Marksman Modifier          (98)
//   EnchFortifyBlockConstantSelf     -> Block Modifier             (99)
//   AlchFortifyOneHanded             -> One-Handed Power Modifier  (135)
//   AlchFortifyTwoHanded             -> Two-Handed Power Modifier  (136)
//   AlchFortifyMarksman              -> Marksman Power Modifier    (137)
//   AlchFortifyBlock                 -> Block Power Modifier       (138)
//
// So each of the three combat surfaces reads *two* values: the enchantment family
// and the potion family. They are not aliases of one another — a worn item moves
// the first and a drunk potion the second — and reading only one would silently
// drop half the sources this item was written to support.
//
// The indices are looked up by vanilla name through `ActorValueIdentity` rather
// than written as numbers, so xEdit's `wbActorValueEnum` stays the single citation
// for what each index is.
//
// ## Why the magnitudes are percentage points
//
// The records' own description strings say so. UESP prints them verbatim per
// effect: "Enchanting description: One-handed attacks do <mag>% more damage"
// (<https://en.uesp.net/wiki/Skyrim:Fortify_One-handed>), "Two-handed attacks do
// <mag>% more damage", "Bows do <mag>% more damage"
// (<https://en.uesp.net/wiki/Skyrim:Fortify_Marksman>) and "Block <mag>% more
// damage with your shield" (<https://en.uesp.net/wiki/Skyrim:Fortify_Block>). So a
// magnitude of 20 is +20% and the multiplier is `1 + points / 100`.
//
// Several sources add rather than multiply: UESP's own worked example — "if you
// have the maximum four items enchanted with these, you will do +160% damage" from
// four 40% items — is additive, and the actor value they share is a single
// accumulator, so summing the points before the division is what the store already
// does for us.
//
// ## What is deliberately not read
//
// `Melee Damage` (34) and `Unarmed Damage` (35) are flat *point* adds a creature's
// records author rather than percentages, and `Attack Damage Mult` (159) is the
// multiplier vanilla perks write. None of the three is read here: this item's scope
// is the enchantment and potion terms, and folding a flat add into a multiplier
// would be a different formula wearing the same name. Named as gaps in
// docs/engine/magic.md.
//
// Documented in docs/engine/magic.md, docs/engine/melee-combat.md and
// docs/engine/archery.md.

import Foundation

/// The fortify multipliers the damage formulas take.
///
/// Pure arithmetic over a value reader, with no store and no world, so every
/// number below is a plain assertion in a test rather than something only a running
/// session can show.
nonisolated enum CombatFortifyBonus {
    /// Percentage points per unit of multiplier. The magnitudes are percentages;
    /// see the file header for the quoted descriptions.
    static let pointsPerWhole: Float = 100

    /// One-Handed Modifier and One-Handed Power Modifier.
    static let oneHandedIndices = indices("One-Handed Modifier", "One-Handed Power Modifier")
    /// Two-Handed Modifier and Two-Handed Power Modifier.
    static let twoHandedIndices = indices("Two-Handed Modifier", "Two-Handed Power Modifier")
    /// Marksman Modifier and Marksman Power Modifier, which is what a bow reads.
    static let archeryIndices = indices("Marksman Modifier", "Marksman Power Modifier")
    /// Block Modifier and Block Power Modifier.
    static let blockIndices = indices("Block Modifier", "Block Power Modifier")

    /// The multiplier a melee swing with `handType` earns.
    ///
    /// Which pair is read follows the animation family the weapon belongs to,
    /// because that is the only thing this engine knows about a swing that
    /// distinguishes one-handed from two-handed. An empty hand reads neither: an
    /// unarmed hit is neither a one-handed nor a two-handed attack, and `Unarmed
    /// Damage` is the value vanilla moves for it (see the file header).
    static func melee(handType: CombatHandType, reading value: (Int32) -> Float?) -> Float {
        switch handType {
        case .sword, .dagger, .axe, .mace: multiplier(of: oneHandedIndices, reading: value)
        case .greatsword, .battleaxe: multiplier(of: twoHandedIndices, reading: value)
        case .bow, .crossbow: multiplier(of: archeryIndices, reading: value)
        default: 1
        }
    }

    /// The multiplier a bow shot earns.
    static func archery(reading value: (Int32) -> Float?) -> Float {
        multiplier(of: archeryIndices, reading: value)
    }

    /// The multiplier a block earns, which multiplies the blocked fraction.
    static func block(reading value: (Int32) -> Float?) -> Float {
        multiplier(of: blockIndices, reading: value)
    }

    /// `1 + points / 100`, summing every index and floored at zero.
    ///
    /// Floored rather than allowed negative because the formulas it feeds treat
    /// their bonus as a non-negative multiplier: a detrimental effect big enough to
    /// take the sum below -100 points would otherwise turn a hit into a heal.
    static func multiplier(of indices: [Int32], reading value: (Int32) -> Float?) -> Float {
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
