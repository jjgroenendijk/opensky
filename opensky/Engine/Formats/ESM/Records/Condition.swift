// CTDA condition entries, the shared "is this true right now?" test attached to
// dozens of record types (MUST, QUST, PERK, INFO, PACK, ...). Every CTDA payload
// is exactly 32 bytes, little-endian:
//   0   uint8   operator (top 3 bits) + flags (low 5 bits)
//   1   3 bytes unused — may hold nonzero garbage, never validated
//   4   4 bytes comparison value: float32, or a GLOB FormID when flag 0x04
//   8   uint16  function index, stored on disk already offset by -4096
//   10  2 bytes padding — may hold nonzero garbage, never validated
//   12  4 bytes parameter #1, typed per function (kept raw here)
//   16  4 bytes parameter #2, typed per function (kept raw here)
//   20  uint32  run-on type
//   24  FormID  reference — only meaningful when run-on == 2 (Reference);
//               xEdit marks it ignored otherwise and it MAY hold garbage
//   28  int32   parameter #3 / run-on index, -1 when unused
// Ambiguity policy: the function index decides how the two parameter words and
// the comparison value should be read, and that registry is not implemented yet
// (issue #251), so the parameters stay raw with typed accessors. Operator and
// run-on values outside the documented sets round-trip through `unknown` rather
// than throwing, and a CTDA payload that is not exactly 32 bytes is skipped —
// malformed plugin data must never crash the engine (AGENTS.md mod-quirk rule).
//
// CITC precedes a condition run and states how many CTDA fields follow. CIS1 and
// CIS2 are zstrings that override parameter #1 / parameter #2 of the
// immediately preceding CTDA; when they are present the raw parameter words are
// arbitrary.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/CTDA Field"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CTDA_Field
//   xEdit dev Core/wbDefinitionsTES5.pas, `wbCTDA` (line 6889)

import Foundation

nonisolated struct Condition: Equatable {
    /// Top 3 bits of the operator byte. 6 and 7 are undefined on disk and are
    /// kept verbatim instead of being forced onto a real comparison.
    enum ComparisonOperator: Equatable {
        case equal
        case notEqual
        case greaterThan
        case greaterThanOrEqual
        case lessThan
        case lessThanOrEqual
        case unknown(UInt8)

        init(rawValue: UInt8) {
            switch rawValue {
            case 0: self = .equal
            case 1: self = .notEqual
            case 2: self = .greaterThan
            case 3: self = .greaterThanOrEqual
            case 4: self = .lessThan
            case 5: self = .lessThanOrEqual
            default: self = .unknown(rawValue)
            }
        }
    }

    /// Low 5 bits of the operator byte.
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt8

        /// This condition ORs with the next one instead of ANDing.
        static let or = Flags(rawValue: 0x01)
        static let useAliases = Flags(rawValue: 0x02)
        /// Comparison value is a GLOB FormID rather than a float.
        static let useGlobal = Flags(rawValue: 0x04)
        static let usePackData = Flags(rawValue: 0x08)
        static let swapSubjectAndTarget = Flags(rawValue: 0x10)
    }

    /// The right-hand side of the comparison: a literal, or the current value
    /// of a global variable when `Flags.useGlobal` is set.
    enum ComparisonValue: Equatable {
        case value(Float)
        case global(FormID)
    }

    /// Which object the function runs against (offset 20).
    enum RunOnType: Equatable {
        case subject
        case target
        case reference
        case combatTarget
        case linkedReference
        case questAlias
        case packageData
        case eventData
        case unknown(UInt32)

        init(rawValue: UInt32) {
            switch rawValue {
            case 0: self = .subject
            case 1: self = .target
            case 2: self = .reference
            case 3: self = .combatTarget
            case 4: self = .linkedReference
            case 5: self = .questAlias
            case 6: self = .packageData
            case 7: self = .eventData
            default: self = .unknown(rawValue)
            }
        }
    }

    /// A raw 4-byte function parameter. The function index picks the real type,
    /// so the word is stored verbatim and reinterpreted on request.
    struct Parameter: Equatable {
        let rawValue: UInt32

        var asFloat: Float {
            Float(bitPattern: rawValue)
        }

        var asFormID: FormID {
            FormID(rawValue)
        }

        var asInt32: Int32 {
            Int32(bitPattern: rawValue)
        }
    }

    let comparison: ComparisonOperator
    let flags: Flags
    let comparisonValue: ComparisonValue
    /// Raw on-disk function index. The Creation Kit numbers these 4096 higher,
    /// so `GetWantBlocking` (CK 4096) is 0 here. Interpreting it is issue #251.
    let functionIndex: UInt16
    let parameter1: Parameter
    let parameter2: Parameter
    let runOn: RunOnType
    /// Offset 24. Meaningful only when `runOn == .reference`; otherwise xEdit
    /// treats it as ignored and it may hold leftover garbage.
    let reference: FormID
    /// Offset 28, called parameter #3 by xEdit and the quest-alias /
    /// package-data index by UESP. -1 means unused. Stored, not interpreted.
    let parameter3: Int32
    /// CIS1 — replaces `parameter1` when the record carries one.
    var parameter1Name: String?
    /// CIS2 — replaces `parameter2` when the record carries one.
    var parameter2Name: String?

    /// Decodes one CTDA field. Returns nil when the payload is not exactly 32
    /// bytes, which is a mod quirk to skip rather than a fatal error.
    init?(ctda field: ESMField) throws {
        guard field.type == "CTDA" else {
            throw ESMError.malformed("expected CTDA field, got \(field.type)")
        }
        guard field.data.count == 32 else { return nil }

        var reader = BinaryReader(field.data)
        let operatorByte = try reader.readUInt8()
        comparison = ComparisonOperator(rawValue: operatorByte >> 5)
        flags = Flags(rawValue: operatorByte & 0x1F)
        reader.skip(3) // unused, may be nonzero
        let comparisonWord = try reader.readUInt32()
        comparisonValue = flags.contains(.useGlobal)
            ? .global(FormID(comparisonWord))
            : .value(Float(bitPattern: comparisonWord))
        functionIndex = try reader.readUInt16()
        reader.skip(2) // padding, may be nonzero
        parameter1 = try Parameter(rawValue: reader.readUInt32())
        parameter2 = try Parameter(rawValue: reader.readUInt32())
        runOn = try RunOnType(rawValue: reader.readUInt32())
        reference = try FormID(reader.readUInt32())
        parameter3 = try Int32(bitPattern: reader.readUInt32())
    }
}

/// Accumulator for a CITC/CTDA/CIS1/CIS2 run inside one record's field loop.
/// Record decoders forward every unrecognised field here and keep whatever it
/// claims, so all condition-bearing record types share one implementation.
nonisolated struct ConditionList: Equatable {
    /// CITC, the authored count of the CTDA fields that follow it. Absent on
    /// many records, and never trusted over the CTDA fields actually decoded:
    /// a record may carry several condition runs (every Skyrim.esm record whose
    /// CITC disagrees with its CTDA count is a PACK, where the CITC covers only
    /// the package's own run and the rest belong to nested package data). The
    /// last CITC seen wins.
    private(set) var declaredCount: Int?
    private(set) var conditions: [Condition] = []

    var isEmpty: Bool {
        conditions.isEmpty
    }

    /// Consumes `field` when it is part of a condition run. Returns false for
    /// anything else so the caller can keep matching its own fields.
    @discardableResult
    mutating func decode(field: ESMField) throws -> Bool {
        switch field.type {
        case "CITC":
            guard field.data.count == 4 else { return true }
            var reader = BinaryReader(field.data)
            declaredCount = try Int(reader.readUInt32())
        case "CTDA":
            if let condition = try Condition(ctda: field) {
                conditions.append(condition)
            }
        case "CIS1":
            try setName(field, keyPath: \.parameter1Name)
        case "CIS2":
            try setName(field, keyPath: \.parameter2Name)
        default:
            return false
        }
        return true
    }

    /// Attaches a CIS1/CIS2 override to the last decoded condition. A run whose
    /// CTDA was skipped leaves nothing to attach to, so the string is dropped.
    private mutating func setName(
        _ field: ESMField,
        keyPath: WritableKeyPath<Condition, String?>
    ) throws {
        guard !conditions.isEmpty else { return }
        var reader = BinaryReader(field.data)
        conditions[conditions.count - 1][keyPath: keyPath] = try reader.readZString()
    }
}
