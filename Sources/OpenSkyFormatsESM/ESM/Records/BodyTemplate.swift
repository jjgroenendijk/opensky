// BOD2/BODT body template shared by ARMO, ARMA, and RACE. Both start with the
// biped slot mask. The 8-byte BODT form is ambiguous after that word, so its
// armor type stays nil. Layout and sources: docs/formats/armor.md.

import Foundation
import OpenSkyFormatsCore

/// Biped object slots an item covers. Bit N == biped slot (30 + N); the named
/// bits follow nif.xml BSDismemberBodyPartType (SBP_30_HEAD ... SBP_61_FX01).
/// Unnamed slots stay reachable through `rawValue`.
nonisolated public struct BodySlots: OptionSet, Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let head = BodySlots(rawValue: 1 << 0) // slot 30
    public static let hair = BodySlots(rawValue: 1 << 1) // slot 31
    public static let body = BodySlots(rawValue: 1 << 2) // slot 32
    public static let hands = BodySlots(rawValue: 1 << 3) // slot 33
    public static let forearms = BodySlots(rawValue: 1 << 4) // slot 34
    public static let amulet = BodySlots(rawValue: 1 << 5) // slot 35
    public static let ring = BodySlots(rawValue: 1 << 6) // slot 36
    public static let feet = BodySlots(rawValue: 1 << 7) // slot 37
    public static let calves = BodySlots(rawValue: 1 << 8) // slot 38
    public static let shield = BodySlots(rawValue: 1 << 9) // slot 39
    public static let tail = BodySlots(rawValue: 1 << 10) // slot 40
    public static let longHair = BodySlots(rawValue: 1 << 11) // slot 41
    public static let circlet = BodySlots(rawValue: 1 << 12) // slot 42
    public static let ears = BodySlots(rawValue: 1 << 13) // slot 43
    public static let decapitatedHead = BodySlots(rawValue: 1 << 20) // slot 50
    public static let decapitate = BodySlots(rawValue: 1 << 21) // slot 51
    public static let fx01 = BodySlots(rawValue: 1 << 31) // slot 61

    /// True when the two sets share at least one slot — the core test for
    /// deciding whether one armature hides another during appearance layout.
    public func overlaps(_ other: BodySlots) -> Bool {
        !isDisjoint(with: other)
    }

    /// The named bits above with their nif.xml names, for readouts. Unnamed
    /// slots stay reachable through `rawValue`; a printer must show them, as
    /// `InventoryCore.describe(_:)` does.
    public static let namedSlots: [(name: String, slots: BodySlots)] = [
        ("head", .head), ("hair", .hair), ("body", .body), ("hands", .hands),
        ("forearms", .forearms), ("amulet", .amulet), ("ring", .ring),
        ("feet", .feet), ("calves", .calves), ("shield", .shield),
        ("tail", .tail), ("long hair", .longHair), ("circlet", .circlet),
        ("ears", .ears), ("decapitated head", .decapitatedHead),
        ("decapitate", .decapitate), ("fx01", .fx01)
    ]
}

/// Armor material class (BOD2/BODT trailing word). Unknown values decode to
/// nil rather than trapping.
nonisolated public enum ArmorType: UInt32, Equatable, Sendable {
    case light = 0
    case heavy = 1
    case clothing = 2
}

nonisolated public struct BodyTemplate: Equatable, Sendable {
    public let slots: BodySlots
    public let armorType: ArmorType?

    /// BOD2: uint32 biped flags + uint32 armor type (8 bytes).
    public init(bod2 field: ESMField) throws {
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
    public init(bodt field: ESMField) throws {
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
