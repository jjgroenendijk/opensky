// ENIT, the enchantment header, with its flag and type vocabulary. The last
// FormID (worn restrictions) is optional, so 32 bytes are required and the
// link is read only when present. Cast type and delivery reuse the MGEF enums.
// Layout and sources: docs/formats/enchantments.md.

import Foundation
import OpenSkyFormatsCore

/// ENIT flags. xEdit names bit 0 "No Auto-Calc" and UESP names the same bit
/// "ManualCalc"; both mean the authored cost wins over the derived one, which
/// is what `SpellFlags.manualCostCalc` means on a spell.
nonisolated public struct EnchantmentFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Bit 0 — the ENIT enchantment cost is authored, not derived.
    public static let manualCostCalc = Self(rawValue: 1 << 0)
    /// Bit 2 — recasting extends the running duration instead of restarting it.
    public static let extendDurationOnRecast = Self(rawValue: 1 << 2)
}

/// ENIT enchantment type. The two documented values are far apart rather than
/// consecutive, so anything else stays an `unknown(raw:)` instead of being
/// folded into either.
nonisolated public enum EnchantmentType: Equatable, CustomStringConvertible, Sendable {
    case enchantment
    case staffEnchantment
    case unknown(raw: UInt32)

    public init(rawValue: UInt32) {
        self = switch rawValue {
        case 0x06: .enchantment
        case 0x0C: .staffEnchantment
        default: .unknown(raw: rawValue)
        }
    }

    public var description: String {
        switch self {
        case .enchantment: "enchantment"
        case .staffEnchantment: "staff enchantment"
        case let .unknown(raw): "unknown(\(raw))"
        }
    }
}

nonisolated public struct EnchantmentItemData: Equatable, Sendable {
    /// The shortest ENIT the decoder accepts: the form-version-37 variant that
    /// omits the worn-restrictions link.
    public static let minimumSize = 32
    /// The full struct, worn-restrictions link included.
    public static let fullSize = 36

    /// Magicka charged per use. Authoritative only under `.manualCostCalc`.
    public let cost: Int32
    public let flags: EnchantmentFlags
    public let castingType: MagicEffectCastingType
    /// Fully charged value of an item carrying this enchantment.
    public let amount: Int32
    public let delivery: MagicEffectDelivery
    public let type: EnchantmentType
    public let chargeTime: Float
    /// The ENCH this one derives from; nil when it is itself a base.
    public let baseEnchantment: FormID?
    /// FLST of the slots this enchantment may be applied to. Nil both when the
    /// link is null and when the payload is the 32-byte variant.
    public let wornRestrictions: FormID?

    /// True when the cost has to be derived from the effect list.
    public var usesAutoCalculatedCost: Bool {
        !flags.contains(.manualCostCalc)
    }

    public var unknownEnumCount: Int {
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

    public init(field: ESMField) throws {
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
