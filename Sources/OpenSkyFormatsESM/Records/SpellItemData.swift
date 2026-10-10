// SPIT, the 36-byte casting header of SPEL and SCRL, with its flag and type
// vocabulary. Casting type and delivery reuse the MGEF enums; SCRL adds its
// own casting value 3, which is why `MagicEffectCastingType` has `.scroll`.
// Layout and sources: docs/formats/magic-records.md.

import Foundation
import OpenSkyFormatsCore

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
    /// PERK that halves the cost. Decoded and left unresolved here.
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
