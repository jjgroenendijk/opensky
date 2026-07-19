// Body Template shared by ARMO, ARMA, and RACE records. Both encodings open
// with a uint32 "First Person Flags" biped-object bitfield naming the body
// slots the item occupies:
//   BOD2 (SSE, plugin format >= 1.6.91): uint32 biped flags + uint32 armor
//        type. 8 bytes.
//   BODT (legacy): uint32 biped flags [+ uint32 general flags] + uint32 armor
//        type. RACE always writes the 12-byte form; ARMO/ARMA accept 8- or
//        12-byte. The 8-byte form omits the general-flags word, so its trailing
//        layout is ambiguous — decode the slots (always the first word) and
//        leave armor type nil there.
// Only the biped slot bits + armor type matter for skinning, so both shapes
// decode to one struct; enchantment/keyword/value data lives elsewhere.
//
// Reference: UESP "Skyrim Mod:Mod File Format/ARMO" + ".../ARMA" + ".../RACE"
// (BOD2/BODT field rows). Slot bit numbering from NifTools nif.xml enum
// BSDismemberBodyPartType: bit N of the uint32 is biped slot (30 + N).

import Foundation

/// Biped object slots an item covers. Bit N == biped slot (30 + N); the named
/// bits follow nif.xml BSDismemberBodyPartType (SBP_30_HEAD ... SBP_61_FX01).
/// Unnamed slots stay reachable through `rawValue`.
nonisolated struct BodySlots: OptionSet, Equatable {
    let rawValue: UInt32

    static let head = BodySlots(rawValue: 1 << 0) // slot 30
    static let hair = BodySlots(rawValue: 1 << 1) // slot 31
    static let body = BodySlots(rawValue: 1 << 2) // slot 32
    static let hands = BodySlots(rawValue: 1 << 3) // slot 33
    static let forearms = BodySlots(rawValue: 1 << 4) // slot 34
    static let amulet = BodySlots(rawValue: 1 << 5) // slot 35
    static let ring = BodySlots(rawValue: 1 << 6) // slot 36
    static let feet = BodySlots(rawValue: 1 << 7) // slot 37
    static let calves = BodySlots(rawValue: 1 << 8) // slot 38
    static let shield = BodySlots(rawValue: 1 << 9) // slot 39
    static let tail = BodySlots(rawValue: 1 << 10) // slot 40
    static let longHair = BodySlots(rawValue: 1 << 11) // slot 41
    static let circlet = BodySlots(rawValue: 1 << 12) // slot 42
    static let ears = BodySlots(rawValue: 1 << 13) // slot 43
    static let decapitatedHead = BodySlots(rawValue: 1 << 20) // slot 50
    static let decapitate = BodySlots(rawValue: 1 << 21) // slot 51
    static let fx01 = BodySlots(rawValue: 1 << 31) // slot 61

    /// True when the two sets share at least one slot — the core test for
    /// deciding whether one armature hides another during appearance layout.
    func overlaps(_ other: BodySlots) -> Bool {
        !isDisjoint(with: other)
    }
}

/// Armor material class (BOD2/BODT trailing word). Unknown values decode to
/// nil rather than trapping.
nonisolated enum ArmorType: UInt32, Equatable {
    case light = 0
    case heavy = 1
    case clothing = 2
}

nonisolated struct BodyTemplate: Equatable {
    let slots: BodySlots
    let armorType: ArmorType?

    /// BOD2: uint32 biped flags + uint32 armor type (8 bytes).
    init(bod2 field: ESMField) throws {
        guard field.data.count >= 4 else {
            throw ESMError.malformed(
                "BOD2 has \(field.data.count) bytes, expected 8"
            )
        }
        var reader = BinaryReader(field.data)
        slots = try BodySlots(rawValue: reader.readUInt32())
        armorType = field.data.count >= 8 ? try ArmorType(rawValue: reader.readUInt32()) : nil
    }

    /// BODT: uint32 biped flags first; armor type is the last word of the
    /// 12-byte form. The 8-byte form omits the general-flags word and leaves
    /// the trailing layout ambiguous, so armor type stays nil there.
    init(bodt field: ESMField) throws {
        guard field.data.count >= 4 else {
            throw ESMError.malformed(
                "BODT has \(field.data.count) bytes, expected 8 or 12"
            )
        }
        var reader = BinaryReader(field.data)
        slots = try BodySlots(rawValue: reader.readUInt32())
        if field.data.count >= 12 {
            reader.skip(4) // general flags — unused for skinning
            armorType = try ArmorType(rawValue: reader.readUInt32())
        } else {
            armorType = nil
        }
    }
}
