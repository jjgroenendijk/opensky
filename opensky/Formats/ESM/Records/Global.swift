// GLOB record decoded into engine types: a named global variable with a
// declared numeric type and a plugin-authored default value.
//
// The one surprise in the layout is that FLTV is a float32 whatever FNAM
// declares, so a "short" or "long" global is a float on disk that happens to
// hold an integral value. UESP spells this out and warns that a long global
// silently loses precision past 2^24 for exactly that reason. OpenSky keeps the
// same representation — one `Float` plus the declared type — and coerces on
// write rather than inventing a wider integer the file cannot round-trip.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/GLOB"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/GLOB
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, `wbRecord(GLOB, 'Global', ...)`
//     https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas
// Layout + runtime policy documented in docs/formats/records.md and
// docs/engine/runtime-state.md.

import Foundation

nonisolated struct Global: Equatable {
    /// FNAM type character. xEdit enumerates exactly three (`s`, `l`, `f`) and
    /// defaults the editor to Float, which is also what OpenSky falls back to
    /// when FNAM is absent or carries a character no open spec describes.
    enum ValueType: Equatable, Sendable, CaseIterable {
        case short
        case long
        case float

        /// Nil for a character outside the documented set, which the decoder
        /// treats as "no usable FNAM" rather than as a fatal error.
        init?(fnam: UInt8) {
            switch fnam {
            case UInt8(ascii: "s"): self = .short
            case UInt8(ascii: "l"): self = .long
            case UInt8(ascii: "f"): self = .float
            default: return nil
            }
        }

        /// The FNAM character this type is written as.
        var fnam: UInt8 {
            switch self {
            case .short: UInt8(ascii: "s")
            case .long: UInt8(ascii: "l")
            case .float: UInt8(ascii: "f")
            }
        }

        /// True for the two integer types, whose values are rounded on every
        /// write so a short or long global never holds a fraction.
        var isInteger: Bool {
            self != .float
        }

        /// Coerces a raw float onto this type.
        ///
        /// Integer types round half away from zero — the everyday "round" that
        /// sends 0.5 to 1 and -0.5 to -1 — because the alternative, truncation
        /// toward zero, makes `set(x + 0.6)` repeated ten times land on 0
        /// instead of 6. Nothing in an open spec states which rule the original
        /// engine used, so this is OpenSky's documented choice
        /// (docs/engine/runtime-state.md). Non-finite input becomes 0 rather
        /// than propagating a NaN through comparisons that must be total.
        /// Nothing is clamped to 16 or 32 bits: the value lives in a float on
        /// disk, and clamping would discard mod data the file can represent.
        func coerce(_ raw: Float) -> Float {
            guard isInteger else { return raw }
            guard raw.isFinite else { return 0 }
            return raw.rounded(.toNearestOrAwayFromZero)
        }
    }

    let formID: FormID
    let editorID: String?
    /// Record header flag 0x40. The Creation Kit forbids editing a constant
    /// global at runtime; OpenSky records the bit and leaves the policy to the
    /// caller rather than silently refusing writes.
    let isConstant: Bool
    /// FNAM type plus the FLTV value, already coerced onto that type.
    let defaultValue: GlobalValue

    var valueType: ValueType {
        defaultValue.type
    }

    init(record: ESMRecord) throws {
        guard record.type == "GLOB" else {
            throw ESMError.malformed("expected GLOB record, got \(record.type)")
        }
        formID = FormID(record.formID)
        isConstant = record.flags.contains(.constantGlobal)

        var editorID: String?
        var type = ValueType.float
        var rawValue: Float = 0
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
                // OBND and VMAD are listed by UESP as vestigial on GLOB —
                // checked for by the game but never present in shipped data.
                break
            }
        }
        self.editorID = editorID
        defaultValue = GlobalValue(type: type, rawValue: rawValue)
    }

    /// Synthetic global, for tests and for callers assembling defaults without
    /// a plugin.
    init(formID: FormID, editorID: String?, value: GlobalValue, isConstant: Bool = false) {
        self.formID = formID
        self.editorID = editorID
        self.isConstant = isConstant
        defaultValue = value
    }
}

/// A global's current numeric value together with the type it was declared as.
///
/// The type travels with the value because every write has to be coerced, and
/// the coercion rule belongs to the global rather than to whoever is writing:
/// a script that stores 3.7 into a short global stores 4, and a condition that
/// reads it back must see 4 whether the write came from Papyrus, the console or
/// a save file.
nonisolated struct GlobalValue: Equatable, Sendable {
    let type: Global.ValueType
    /// Value already coerced onto `type`; never a fraction for short or long.
    let value: Float

    init(type: Global.ValueType, rawValue: Float) {
        self.type = type
        value = type.coerce(rawValue)
    }

    /// The value as an integer, for a short or long global. Nil for a float
    /// global and for a magnitude no `Int64` can hold.
    var integerValue: Int64? {
        guard type.isInteger, value >= -9.223_372e18, value <= 9.223_372e18 else { return nil }
        return Int64(value)
    }
}
