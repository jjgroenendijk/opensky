// ENIT, the enchantment header ENCH carries, plus its flag and
// enchantment-type vocabulary.
//
//   0x00 int32   enchantment cost — the magicka the enchantment charges per
//                use. Authoritative only when the manual-cost flag is set;
//                otherwise the game derives it from the effects, the same way
//                a spell derives its cost (see SpellCost.swift).
//   0x04 uint32  flags
//   0x08 uint32  cast type
//   0x0C int32   enchantment amount — the fully charged value of an item
//                carrying this enchantment
//   0x10 uint32  delivery
//   0x14 uint32  enchantment type: 0x06 enchantment, 0x0C staff enchantment
//   0x18 float32 charge time
//   0x1C FormID  base enchantment — the ENCH this one derives from
//   0x20 FormID  worn restrictions — an FLST of enchantable slots, written
//                only on a base enchantment
//
// The last FormID is optional: UESP records a 32-byte form-version-37 variant
// that omits it, and xEdit marks the same member `SetOptionalFrom(8)`. So the
// decoder requires 32 bytes and reads the worn-restrictions link only when the
// payload is long enough to hold it.
//
// Cast type and delivery reuse the MGEF vocabulary, because xEdit types both
// with the same `wbCastEnum` and `wbDeliveryEnum` it uses for MGEF and SPEL.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/ENCH"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ENCH
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(ENCH, 'Enchantment',
//     ...)` line 5011 — the ordered ENIT struct and its two enums.
// Layout documented in docs/formats/magic-records.md.

import Foundation

/// ENIT flags. xEdit names bit 0 "No Auto-Calc" and UESP names the same bit
/// "ManualCalc"; both mean the authored cost wins over the derived one, which
/// is what `SpellFlags.manualCostCalc` means on a spell.
nonisolated struct EnchantmentFlags: OptionSet, Equatable {
    let rawValue: UInt32

    /// Bit 0 — the ENIT enchantment cost is authored, not derived.
    static let manualCostCalc = Self(rawValue: 1 << 0)
    /// Bit 2 — recasting extends the running duration instead of restarting it.
    static let extendDurationOnRecast = Self(rawValue: 1 << 2)
}

/// ENIT enchantment type. The two documented values are far apart rather than
/// consecutive, so anything else stays an `unknown(raw:)` instead of being
/// folded into either.
nonisolated enum EnchantmentType: Equatable, CustomStringConvertible {
    case enchantment
    case staffEnchantment
    case unknown(raw: UInt32)

    init(rawValue: UInt32) {
        self = switch rawValue {
        case 0x06: .enchantment
        case 0x0C: .staffEnchantment
        default: .unknown(raw: rawValue)
        }
    }

    var description: String {
        switch self {
        case .enchantment: "enchantment"
        case .staffEnchantment: "staff enchantment"
        case let .unknown(raw): "unknown(\(raw))"
        }
    }
}

nonisolated struct EnchantmentItemData: Equatable {
    /// The shortest ENIT the decoder accepts: the form-version-37 variant that
    /// omits the worn-restrictions link.
    static let minimumSize = 32
    /// The full struct, worn-restrictions link included.
    static let fullSize = 36

    /// Magicka charged per use. Authoritative only under `.manualCostCalc`.
    let cost: Int32
    let flags: EnchantmentFlags
    let castingType: MagicEffectCastingType
    /// Fully charged value of an item carrying this enchantment.
    let amount: Int32
    let delivery: MagicEffectDelivery
    let type: EnchantmentType
    let chargeTime: Float
    /// The ENCH this one derives from; nil when it is itself a base.
    let baseEnchantment: FormID?
    /// FLST of the slots this enchantment may be applied to. Nil both when the
    /// link is null and when the payload is the 32-byte variant.
    let wornRestrictions: FormID?

    /// True when the cost has to be derived from the effect list.
    var usesAutoCalculatedCost: Bool {
        !flags.contains(.manualCostCalc)
    }

    var unknownEnumCount: Int {
        var count = 0
        if case .unknown = castingType {
            count += 1
        }
        if case .unknown = delivery {
            count += 1
        }
        if case .unknown = type {
            count += 1
        }
        return count
    }

    init(field: ESMField) throws {
        guard field.data.count >= Self.minimumSize else {
            throw ESMError.malformed(
                "\(field.type) ENIT has \(field.data.count) bytes, expected "
                    + "at least \(Self.minimumSize)"
            )
        }
        var reader = BinaryReader(field.data)
        cost = try Int32(bitPattern: reader.readUInt32())
        flags = try EnchantmentFlags(rawValue: reader.readUInt32())
        castingType = try MagicEffectCastingType(rawValue: reader.readUInt32())
        amount = try Int32(bitPattern: reader.readUInt32())
        delivery = try MagicEffectDelivery(rawValue: reader.readUInt32())
        type = try EnchantmentType(rawValue: reader.readUInt32())
        chargeTime = try reader.readFloat32()
        baseEnchantment = try Self.link(reader.readUInt32())
        guard field.data.count >= Self.fullSize else {
            wornRestrictions = nil
            return
        }
        wornRestrictions = try Self.link(reader.readUInt32())
    }

    private static func link(_ raw: UInt32) -> FormID? {
        let id = FormID(raw)
        return id.isNull ? nil : id
    }
}
