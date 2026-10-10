// CTDA condition entries (32 bytes), with CITC counts and CIS1/CIS2 parameter
// overrides. Parameters stay raw, because their meaning depends on the
// function. Unknown enum values round-trip through `unknown`, and a CTDA of
// the wrong size is skipped. Layout and sources: docs/formats/conditions.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Condition: Equatable, Sendable {
    /// Top 3 bits of the operator byte. 6 and 7 are undefined on disk and are
    /// kept verbatim instead of being forced onto a real comparison.
    public enum ComparisonOperator: Equatable, Sendable {
        case equal
        case notEqual
        case greaterThan
        case greaterThanOrEqual
        case lessThan
        case lessThanOrEqual
        case unknown(UInt8)

        public init(rawValue: UInt8) {
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
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        /// This condition ORs with the next one instead of ANDing.
        public static let or = Flags(rawValue: 0x01)
        public static let useAliases = Flags(rawValue: 0x02)
        /// Comparison value is a GLOB FormID rather than a float.
        public static let useGlobal = Flags(rawValue: 0x04)
        public static let usePackData = Flags(rawValue: 0x08)
        public static let swapSubjectAndTarget = Flags(rawValue: 0x10)
    }

    /// The right-hand side of the comparison: a literal, or the current value
    /// of a global variable when `Flags.useGlobal` is set.
    public enum ComparisonValue: Equatable, Sendable {
        case value(Float)
        case global(FormID)
    }

    /// Which object the function runs against (offset 20).
    public enum RunOnType: Equatable, Sendable {
        case subject
        case target
        case reference
        case combatTarget
        case linkedReference
        case questAlias
        case packageData
        case eventData
        case unknown(UInt32)

        public init(rawValue: UInt32) {
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
    public struct Parameter: Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public var asFloat: Float {
            Float(bitPattern: rawValue)
        }

        public var asFormID: FormID {
            FormID(stored: rawValue)
        }

        public var asInt32: Int32 {
            Int32(bitPattern: rawValue)
        }
    }

    public let comparison: ComparisonOperator
    public let flags: Flags
    public private(set) var comparisonValue: ComparisonValue
    /// Raw on-disk function index. The Creation Kit numbers these 4096 higher,
    /// so `GetWantBlocking` (CK 4096) is 0 here.
    public let functionIndex: UInt16
    public private(set) var parameter1: Parameter
    public private(set) var parameter2: Parameter
    public let runOn: RunOnType
    /// Offset 24. Meaningful only when `runOn == .reference`; otherwise xEdit
    /// treats it as ignored and it may hold leftover garbage.
    public private(set) var reference: FormID
    /// Offset 28, called parameter #3 by xEdit and the quest-alias /
    /// package-data index by UESP. -1 means unused. Stored, not interpreted.
    public let parameter3: Int32
    /// CIS1 — replaces `parameter1` when the record carries one.
    public var parameter1Name: String?
    /// CIS2 — replaces `parameter2` when the record carries one.
    public var parameter2Name: String?

    /// A condition nothing authored, for callers that want a function's value
    /// rather than a verdict. The comparison is `>= 0`, which every documented
    /// return value meets. `ConditionProbe` is the caller.
    public init(
        probingFunction functionIndex: UInt16,
        parameter1: UInt32 = 0,
        parameter2: UInt32 = 0,
        runOn: RunOnType = .subject
    ) {
        comparison = .greaterThanOrEqual
        flags = []
        comparisonValue = .value(0)
        self.functionIndex = functionIndex
        self.parameter1 = Parameter(rawValue: parameter1)
        self.parameter2 = Parameter(rawValue: parameter2)
        self.runOn = runOn
        reference = FormID(0)
        parameter3 = -1
    }

    /// Decodes one CTDA field. Returns nil when the payload is not exactly 32
    /// bytes, which is a mod quirk to skip rather than a fatal error.
    public init?(ctda field: ESMField) throws {
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
            ? .global(FormID(stored: comparisonWord))
            : .value(Float(bitPattern: comparisonWord))
        functionIndex = try reader.readUInt16()
        reader.skip(2) // padding, may be nonzero
        parameter1 = try Parameter(rawValue: reader.readUInt32())
        parameter2 = try Parameter(rawValue: reader.readUInt32())
        runOn = try RunOnType(rawValue: reader.readUInt32())
        // Conditions stay as written; the evaluator translates them by function.
        reference = try FormID(stored: reader.readUInt32())
        parameter3 = try Int32(bitPattern: reader.readUInt32())
    }
}

nonisolated extension Condition {
    /// A copy with its FormID words passed through `translate`. Only the function
    /// knows which parameter words are FormIDs, so the caller names them.
    public func translatingFormIDs(
        parameter1 translatesParameter1: Bool,
        parameter2 translatesParameter2: Bool,
        _ translate: (FormID) -> FormID
    ) -> Condition {
        var copy = self
        if translatesParameter1 {
            copy.parameter1 = Parameter(rawValue: translate(parameter1.asFormID).rawValue)
        }
        if translatesParameter2 {
            copy.parameter2 = Parameter(rawValue: translate(parameter2.asFormID).rawValue)
        }
        if runOn == .reference {
            copy.reference = translate(reference)
        }
        if case let .global(id) = comparisonValue {
            copy.comparisonValue = .global(translate(id))
        }
        return copy
    }
}

/// Accumulator for a CITC/CTDA/CIS1/CIS2 run inside one record's field loop.
/// Record decoders forward every unrecognised field here and keep whatever it
/// claims, so all condition-bearing record types share one implementation.
nonisolated public struct ConditionList: Equatable, Sendable {
    /// CITC, the authored count of the CTDA fields that follow it. Absent on
    /// many records, and never trusted over the CTDA fields actually decoded:
    /// a record may carry several condition runs (every Skyrim.esm record whose
    /// CITC disagrees with its CTDA count is a PACK, where the CITC covers only
    /// the package's own run and the rest belong to nested package data). The
    /// last CITC seen wins.
    public private(set) var declaredCount: Int?
    public private(set) var conditions: [Condition] = []

    public var isEmpty: Bool {
        conditions.isEmpty
    }

    /// Whether `decode(field:)` would claim this field type. Record decoders
    /// that route a CTDA run to one of several lists — PERK picks the perk's
    /// own conditions or the open entry-point tab — ask this before choosing
    /// which list to hand the field to.
    public static func isConditionField(_ type: FourCC) -> Bool {
        type == "CITC" || type == "CTDA" || type == "CIS1" || type == "CIS2"
    }

    /// Consumes `field` when it is part of a condition run. Returns false for
    /// anything else so the caller can keep matching its own fields.
    @discardableResult
    public mutating func decode(field: ESMField) throws -> Bool {
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
