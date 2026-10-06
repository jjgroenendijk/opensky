// GLOB global variable. FLTV is a float32 whatever FNAM declares, so OpenSky
// keeps one `Float` plus the declared type and coerces on write.
// Layout: docs/formats/records.md. Policy: docs/engine/global-variables.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Global: Equatable, Sendable {
    /// FNAM type character. xEdit enumerates exactly three (`s`, `l`, `f`) and
    /// defaults the editor to Float, which is also what OpenSky falls back to
    /// when FNAM is absent or carries a character no open spec describes.
    public enum ValueType: Equatable, Sendable, CaseIterable {
        case short
        case long
        case float

        /// Nil for a character outside the documented set, which the decoder
        /// treats as "no usable FNAM" rather than as a fatal error.
        public init?(fnam: UInt8) {
            switch fnam {
            case UInt8(ascii: "s"): self = .short
            case UInt8(ascii: "l"): self = .long
            case UInt8(ascii: "f"): self = .float
            default: return nil
            }
        }

        /// The FNAM character this type is written as.
        public var fnam: UInt8 {
            switch self {
            case .short: UInt8(ascii: "s")
            case .long: UInt8(ascii: "l")
            case .float: UInt8(ascii: "f")
            }
        }

        /// True for the two integer types, whose values are rounded on every
        /// write so a short or long global never holds a fraction.
        public var isInteger: Bool {
            self != .float
        }

        /// Coerces a raw float onto this type. Integers round half away from
        /// zero, non-finite input becomes 0, and nothing is clamped to 16 or
        /// 32 bits. See docs/engine/global-variables.md.
        public func coerce(_ raw: Float) -> Float {
            guard isInteger else { return raw }
            guard raw.isFinite else { return 0 }
            return raw.rounded(.toNearestOrAwayFromZero)
        }
    }

    public let formID: FormID
    public let editorID: String?
    /// Record header flag 0x40. The Creation Kit forbids editing a constant
    /// global at runtime; OpenSky records the bit and leaves the policy to the
    /// caller rather than silently refusing writes.
    public let isConstant: Bool
    /// FNAM type plus the FLTV value, already coerced onto that type.
    public let defaultValue: GlobalValue

    public var valueType: ValueType {
        defaultValue.type
    }

    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        guard record.type == "GLOB" else {
            throw ESMError.malformed("expected GLOB record, got \(record.type)")
        }
        formID = FormID(record.formID)
        isConstant = record.flags.contains(.constantGlobal)

        var editorID: String?
        var type = ValueType.float
        var rawValue: Float = 0
        var skipped = FieldTally()
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FNAM":
                // One byte. A wrong-size FNAM, or a character outside the
                // documented s/l/f set, leaves the xEdit default (Float) in
                // place: an unreadable type must not cost the record its
                // identity or its value.
                guard field.data.count == 1, let declared = try ValueType(fnam: reader.readUInt8())
                else { continue }
                type = declared
            case "FLTV":
                // float32 regardless of what FNAM declared (UESP).
                guard field.data.count == 4 else { continue }
                rawValue = try reader.readFloat32()
            default:
                skipped.note(.unknownField(field.type))
            }
        }
        self.skipped = skipped
        self.editorID = editorID
        defaultValue = GlobalValue(type: type, rawValue: rawValue)
    }

    /// Synthetic global, for tests and for callers assembling defaults without
    /// a plugin.
    public init(formID: FormID, editorID: String?, value: GlobalValue, isConstant: Bool = false) {
        self.formID = formID
        self.editorID = editorID
        self.isConstant = isConstant
        defaultValue = value
        skipped = FieldTally()
    }
}

/// A global's current value with its declared type. The type travels with the
/// value because every write is coerced by the global's own rule, whoever
/// writes it.
nonisolated public struct GlobalValue: Equatable, Sendable {
    public let type: Global.ValueType
    /// Value already coerced onto `type`; never a fraction for short or long.
    public let value: Float

    public init(type: Global.ValueType, rawValue: Float) {
        self.type = type
        value = type.coerce(rawValue)
    }

    /// The value as an integer, for a short or long global. Nil for a float
    /// global and for a magnitude no `Int64` can hold.
    public var integerValue: Int64? {
        guard type.isInteger, value >= -9.223_372e18, value <= 9.223_372e18 else { return nil }
        return Int64(value)
    }
}
