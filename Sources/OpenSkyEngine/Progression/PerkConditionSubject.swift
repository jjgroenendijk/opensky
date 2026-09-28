// Which object each PRKC condition tab of a perk effect runs against (issue
// #497, roadmap item 20.4).
//
// A perk entry-point effect carries one to three condition tabs, and the tab's
// PRKC byte is an index rather than a name: UESP describes it as "Type - How to
// apply the conditions that follow. Has values of 0-2 but the actual values
// depend on the effect type. See the entry point EffectTypes for details"
// (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/PERK>). The per-entry-
// point "Condition Types" column on the same page is what says which subject
// each index names, and this file is that column, transcribed.
//
// Two entry points the name table carries are absent from UESP's effect-type
// table — 12 (`Mod Addiction Duration`) and 91 (`Allow Mount Actor`), neither of
// which any vanilla perk hooks — and both fall back to the perk owner alone.
//
// ## Why this matters at runtime
//
// A caller evaluating an entry point can bind some of these subjects and not
// others. A melee formula knows the attacker and the target; it does not know
// the *weapon* as a world reference, because a swung weapon is an inventory
// FormID rather than a placed reference the condition machinery can run
// `HasKeyword` against. `PerkRuntime` therefore skips a tab whose subject the
// caller did not bind and counts it, rather than evaluating it against the
// wrong object or refusing the whole effect. That is a documented
// over-application — `Armsman00`'s weapon-type tab is exactly such a tab — and
// the count is what makes it visible instead of silent. See docs/engine/perks.md.

import Foundation

/// One object a perk effect's condition tab may run against.
nonisolated enum PerkConditionSubject: String, CaseIterable, Hashable, Sendable {
    /// The actor that owns the perk, which is tab 0 of every entry point.
    case perkOwner
    case target
    case attacker
    case attackerWeapon
    case spell
    case weapon
    case item
    case enchantment
    case lockedReference

    var describedName: String {
        switch self {
        case .perkOwner: "perk owner"
        case .target: "target"
        case .attacker: "attacker"
        case .attackerWeapon: "attacker weapon"
        case .spell: "spell"
        case .weapon: "weapon"
        case .item: "item"
        case .enchantment: "enchantment"
        case .lockedReference: "locked reference"
        }
    }
}

nonisolated extension PerkEntryPoint {
    /// The subjects this entry point's condition tabs run against, in tab
    /// order. An entry point outside the transcribed table answers with the
    /// perk owner alone, which is tab 0 everywhere it is documented.
    var conditionSubjects: [PerkConditionSubject] {
        PerkConditionSubject.table[rawValue] ?? [.perkOwner]
    }

    /// The subject tab `index` runs against, or nil when the record declared
    /// more tabs than the entry point documents.
    func conditionSubject(atTab index: Int) -> PerkConditionSubject? {
        let subjects = conditionSubjects
        guard index >= 0, index < subjects.count else { return nil }
        return subjects[index]
    }
}

nonisolated extension PerkConditionSubject {
    /// Entry-point id to its ordered condition subjects, transcribed from
    /// UESP's "Perk Effect Types" table.
    static let table: [UInt8: [PerkConditionSubject]] = [
        0: [.perkOwner, .weapon, .target],
        1: [.perkOwner, .weapon, .target],
        2: [.perkOwner, .weapon, .target],
        3: [.perkOwner, .item],
        4: [.perkOwner, .attacker, .attackerWeapon],
        5: [.perkOwner],
        6: [.perkOwner],
        7: [.perkOwner, .attacker],
        8: [.perkOwner, .target],
        9: [.perkOwner, .target],
        10: [.perkOwner],
        11: [.perkOwner],
        13: [.perkOwner],
        14: [.perkOwner, .target],
        15: [.perkOwner],
        16: [.perkOwner],
        17: [.perkOwner, .weapon, .target],
        18: [.perkOwner, .weapon, .target],
        19: [.perkOwner],
        20: [.perkOwner, .weapon],
        21: [.perkOwner],
        22: [.perkOwner],
        23: [.perkOwner],
        24: [.perkOwner],
        25: [.perkOwner, .target],
        26: [.perkOwner, .target],
        27: [.perkOwner, .weapon],
        28: [.perkOwner, .weapon, .target],
        29: [.perkOwner, .spell, .target],
        30: [.perkOwner, .spell, .target],
        31: [.perkOwner, .spell, .target],
        32: [.perkOwner, .item],
        33: [.perkOwner, .attacker],
        34: [.perkOwner, .target],
        35: [.perkOwner, .weapon, .target],
        36: [.perkOwner, .attacker, .attackerWeapon],
        37: [.perkOwner, .weapon, .target],
        38: [.perkOwner, .spell],
        39: [.perkOwner],
        40: [.perkOwner],
        41: [.perkOwner, .spell],
        42: [.perkOwner, .spell],
        43: [.perkOwner, .target],
        44: [.perkOwner],
        45: [.perkOwner, .target],
        46: [.perkOwner, .target],
        47: [.perkOwner, .target],
        48: [.perkOwner, .target],
        49: [.perkOwner, .item],
        50: [.perkOwner, .weapon],
        51: [.perkOwner, .weapon, .target],
        52: [.perkOwner, .target],
        53: [.perkOwner, .spell, .target],
        54: [.perkOwner],
        55: [.perkOwner, .spell],
        56: [.perkOwner, .target, .item],
        57: [.perkOwner, .target],
        58: [.perkOwner],
        59: [.perkOwner, .lockedReference],
        60: [.perkOwner, .target],
        61: [.perkOwner, .target, .item],
        62: [.perkOwner],
        63: [.perkOwner],
        64: [.perkOwner],
        65: [.perkOwner],
        66: [.perkOwner],
        67: [.perkOwner, .attacker, .attackerWeapon],
        68: [.perkOwner, .spell],
        69: [.perkOwner],
        70: [.perkOwner, .spell],
        71: [.perkOwner, .spell],
        72: [.perkOwner, .spell],
        73: [.perkOwner],
        74: [.perkOwner, .target],
        75: [.perkOwner, .spell],
        76: [.perkOwner, .item],
        77: [.perkOwner, .enchantment, .item],
        78: [.perkOwner, .target, .item],
        79: [.perkOwner, .enchantment, .item],
        80: [.perkOwner],
        81: [.perkOwner, .target],
        82: [.perkOwner],
        83: [.perkOwner, .weapon, .spell],
        84: [.perkOwner, .target, .item],
        85: [.perkOwner, .item],
        86: [.perkOwner, .lockedReference],
        87: [.perkOwner, .item],
        88: [.perkOwner, .spell],
        89: [.perkOwner, .spell],
        90: [.perkOwner, .lockedReference]
    ]
}
