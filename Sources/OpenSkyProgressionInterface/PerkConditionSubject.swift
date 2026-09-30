// Which object each PRKC condition tab of a perk effect runs against. The PRKC
// byte is an index whose meaning depends on the entry point; this file
// transcribes UESP's "Condition Types" column
// (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/PERK>). Entry points 12
// and 91 are missing there and fall back to the perk owner. An unbound subject
// is skipped and counted by `PerkRuntime`. See docs/engine/perks.md.

import Foundation
import OpenSkyFormatsESM

/// One object a perk effect's condition tab may run against.
nonisolated public enum PerkConditionSubject: String, CaseIterable, Hashable, Sendable {
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
}

nonisolated extension PerkEntryPoint {
    /// The subjects this entry point's condition tabs run against, in tab
    /// order. An entry point outside the transcribed table answers with the
    /// perk owner alone, which is tab 0 everywhere it is documented.
    public var conditionSubjects: [PerkConditionSubject] {
        PerkConditionSubject.table[rawValue] ?? [.perkOwner]
    }

    /// The subject tab `index` runs against, or nil when the record declared
    /// more tabs than the entry point documents.
    public func conditionSubject(atTab index: Int) -> PerkConditionSubject? {
        let subjects = conditionSubjects
        guard index >= 0, index < subjects.count else { return nil }
        return subjects[index]
    }
}

nonisolated extension PerkConditionSubject {
    /// Entry-point id to its ordered condition subjects, transcribed from
    /// UESP's "Perk Effect Types" table.
    public static let table: [UInt8: [PerkConditionSubject]] = [
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
