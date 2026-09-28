// SPIT, the 36-byte casting header SPEL and SCRL share, plus its flag and
// spell-type vocabulary.
//
//   0x00 uint32  base cost — the authored magicka cost. Meaningful only when
//                the manual-cost flag is set; otherwise the game derives the
//                cost from the effects (see SpellCost.swift).
//   0x04 uint32  flags
//   0x08 uint32  spell type
//   0x0C float32 charge time
//   0x10 uint32  casting type
//   0x14 uint32  delivery
//   0x18 float32 cast duration — minimum duration of a concentration spell
//   0x1C float32 range — used by the target-actor and target-location deliveries
//   0x20 FormID  PERK that halves the cost
//
// Casting type and delivery reuse the MGEF vocabulary because xEdit types both
// with the same `wbCastEnum` and `wbDeliveryEnum` definitions it uses for MGEF.
// Scrolls are the one exception: xEdit gives SCRL its own casting enum whose
// only member is 3, "Scroll", which is why `MagicEffectCastingType` carries a
// `.scroll` case that no MGEF ever uses.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/SPEL"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SPEL
//   UESP "Skyrim Mod:Mod File Format/SCRL"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SCRL
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(SPEL, 'Spell', ...)`
//     line 9980 and `wbRecord(SCRL, 'Scroll', ...)` line 10025 — the same
//     ordered SPIT struct in both.
// Layout documented in docs/formats/magic-records.md.

import Foundation

/// SPIT flags. The bit numbers are shared by SPEL and SCRL, but bit 20 means
/// different things in the two records: xEdit names it "Ignore Resistance" on
/// SPEL and "Script Effect Always Applies" on SCRL, so both names are exposed
/// over the same bit rather than one being guessed for the other.
nonisolated public struct SpellFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Bit 0 — the SPIT base cost is authored, not derived from the effects.
    public static let manualCostCalc = Self(rawValue: 1 << 0)
    /// Bit 16 — xEdit "Unknown 16"; vanilla sets it together with bit 18.
    public static let unknown16 = Self(rawValue: 1 << 16)
    public static let pcStartSpell = Self(rawValue: 1 << 17)
    /// Bit 18 — xEdit "Unknown 18"; vanilla sets it together with bit 16.
    public static let unknown18 = Self(rawValue: 1 << 18)
    public static let areaEffectIgnoresLineOfSight = Self(rawValue: 1 << 19)
    /// Bit 20 on SPEL.
    public static let ignoreResistance = Self(rawValue: 1 << 20)
    /// Bit 20 on SCRL — the same bit under the name xEdit gives it there.
    public static let scriptEffectAlwaysApplies = Self(rawValue: 1 << 20)
    public static let disallowAbsorbReflect = Self(rawValue: 1 << 21)
    /// Bit 22 — xEdit "Unknown 22".
    public static let unknown22 = Self(rawValue: 1 << 22)
    public static let noDualCastModifications = Self(rawValue: 1 << 23)
}

/// SPIT spell type. SCRL writes 0 in this word, which xEdit labels "Scroll"
/// for that record; the decoded value stays `.spell` and the record type is
/// what distinguishes a scroll.
nonisolated public enum SpellType: Equatable, CustomStringConvertible, Sendable {
    case spell
    case disease
    case power
    case lesserPower
    case ability
    case poison
    case addiction
    case voice
    case unknown(raw: UInt32)

    public init(rawValue: UInt32) {
        self = switch rawValue {
        case 0: .spell
        case 1: .disease
        case 2: .power
        case 3: .lesserPower
        case 4: .ability
        case 5: .poison
        case 10: .addiction
        case 11: .voice
        default: .unknown(raw: rawValue)
        }
    }

    public var description: String {
        switch self {
        case .spell: "spell"
        case .disease: "disease"
        case .power: "power"
        case .lesserPower: "lesser power"
        case .ability: "ability"
        case .poison: "poison"
        case .addiction: "addiction"
        case .voice: "voice"
        case let .unknown(raw): "unknown(\(raw))"
        }
    }
}

nonisolated public struct SpellItemData: Equatable, Sendable {
    /// The magicka cost stored in the record. Authoritative only when
    /// `flags` contains `.manualCostCalc`.
    public let baseCost: UInt32
    public let flags: SpellFlags
    public let type: SpellType
    public let chargeTime: Float
    public let castingType: MagicEffectCastingType
    public let delivery: MagicEffectDelivery
    /// Minimum duration of a concentration spell.
    public let castDuration: Float
    public let range: Float
    /// PERK that halves the cost. Decoded and left unresolved: perks are M20.
    public let halfCostPerk: FormID?

    /// True when the cost has to be derived from the effect list.
    public var usesAutoCalculatedCost: Bool {
        !flags.contains(.manualCostCalc)
    }

    public var unknownEnumCount: Int {
        var count = 0
        if case .unknown = type {
            count += 1
        }
        if case .unknown = castingType {
            count += 1
        }
        if case .unknown = delivery {
            count += 1
        }
        return count
    }

    public init(field: ESMField) throws {
        guard field.data.count >= 36 else {
            throw ESMError.malformed(
                "\(field.type) SPIT has \(field.data.count) bytes, expected 36"
            )
        }
        var reader = BinaryReader(field.data)
        baseCost = try reader.readUInt32()
        flags = try SpellFlags(rawValue: reader.readUInt32())
        type = try SpellType(rawValue: reader.readUInt32())
        chargeTime = try reader.readFloat32()
        castingType = try MagicEffectCastingType(rawValue: reader.readUInt32())
        delivery = try MagicEffectDelivery(rawValue: reader.readUInt32())
        castDuration = try reader.readFloat32()
        range = try reader.readFloat32()
        let perk = try FormID(reader.readUInt32())
        halfCostPerk = perk.isNull ? nil : perk
    }
}
