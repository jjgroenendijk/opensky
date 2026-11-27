// Counts, per stored field of the decoded record types, the records that carry a value in
// it, so the gap report can rank the fields no engine code reads (docs/tools/gaps.md).
// It reads the values through reflection, so a new field is counted with no edit here. It
// also counts the flag bits and enum cases each field holds, for the flags and enums areas.

import Foundation
public import OpenSkyFormatsCore

nonisolated public struct RecordFieldCensus: Sendable {
    public struct Field: Sendable, Equatable {
        /// Records with a value in the field.
        public var records = 0
        /// The same count per record type, as one Swift type can decode several.
        public var recordTypes: [FourCC: Int] = [:]
    }

    public enum ValueKind: Hashable, Sendable {
        case bit(UInt64)
        /// The case name; `unknown 7` for an `unknown` case that keeps the raw value.
        case enumCase(String)
    }

    /// One value a field holds: a set bit of an `OptionSet`, or an enum case.
    public struct Value: Hashable, Sendable {
        /// The field, `Weapon.flags`.
        public let field: String
        /// The value's type, `Weapon.Flags`.
        public let type: String
        public let kind: ValueKind
    }

    /// Fields keyed `Type.Nested.field`, as `tools/lint-index/record-field-reads.py` writes them.
    public private(set) var fields: [String: Field] = [:]
    /// The bits and cases the fields hold, each counted once per record.
    public private(set) var values: [Value: Field] = [:]
    /// Records per enum type whose case reflection cannot name, because the type prints a
    /// `description` of its own.
    public private(set) var unnamedEnums: [String: Int] = [:]
    /// Records per plain integer field named like `flags`: its bits have no names to test.
    public private(set) var plainFlagFields: [String: Int] = [:]
    /// Only types of this module have fields to count; others, such as `FormID`, are values.
    private let module: String
    private var typeNames: [ObjectIdentifier: String?] = [:]

    public init(module: String = "OpenSkyFormatsESM") {
        self.module = module + "."
    }

    /// Counts the fields `value` fills, each once per record however many entries hold it.
    public mutating func record(_ value: Any, type: FourCC) {
        var found = Found()
        _ = visit(value, found: &found)
        for key in found.fields {
            fields[key, default: Field()].records += 1
            fields[key, default: Field()].recordTypes[type, default: 0] += 1
        }
        for key in found.values {
            values[key, default: Field()].records += 1
            values[key, default: Field()].recordTypes[type, default: 0] += 1
        }
        for name in found.unnamedEnums {
            unnamedEnums[name, default: 0] += 1
        }
        for name in found.plainFlags {
            plainFlagFields[name, default: 0] += 1
        }
    }

    /// What one record fills.
    private struct Found {
        var fields: Set<String> = []
        var values: Set<Value> = []
        var unnamedEnums: Set<String> = []
        var plainFlags: Set<String> = []
    }

    /// Records whether `value` carries a value: a present optional, a non-empty list or text,
    /// a non-zero number, a true flag, any enum case, or a struct with such a field.
    private mutating func visit(_ value: Any, found: inout Found) -> Bool {
        if let carries = Self.scalarCarries(value) {
            return carries
        }
        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .optional:
            guard let wrapped = mirror.children.first else { return false }
            _ = visit(wrapped.value, found: &found)
            return true
        case .collection, .set, .dictionary:
            var empty = true
            for child in mirror.children {
                empty = false
                _ = visit(child.value, found: &found)
            }
            return !empty
        case .struct, .class:
            let owner = typeName(of: value)
            var carries = false
            for child in mirror.children {
                guard
                    let label = child.label, Self.isField(label),
                    visit(child.value, found: &found) else { continue }
                carries = true
                if let owner {
                    let field = "\(owner).\(label)"
                    found.fields.insert(field)
                    noteValues(child.value, field: field, found: &found)
                }
            }
            return carries
        case .enum, .tuple:
            var carries = mirror.displayStyle == .enum
            for child in mirror.children where visit(child.value, found: &found) {
                carries = true
            }
            return carries
        default:
            return true
        }
    }

    /// The bits or the case a field holds, through optionals and lists.
    private mutating func noteValues(_ value: Any, field: String, found: inout Found) {
        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .optional, .collection, .set:
            for child in mirror.children {
                noteValues(child.value, field: field, found: &found)
            }
            return
        default:
            break
        }
        if let set = value as? any OptionSet, let type = typeName(of: value) {
            var rest = Self.bits(of: set)
            while rest != 0 {
                let bit = rest & (~rest &+ 1)
                found.values.insert(Value(field: field, type: type, kind: .bit(bit)))
                rest &= rest - 1
            }
        } else if mirror.displayStyle == .enum, let type = typeName(of: value) {
            if let name = Self.caseName(value, mirror: mirror) {
                found.values.insert(Value(field: field, type: type, kind: .enumCase(name)))
            } else {
                found.unnamedEnums.insert(type)
            }
        } else if
            field.lowercased().hasSuffix("flags"), Self.scalarCarries(value) == true,
            value is any BinaryInteger
        {
            found.plainFlags.insert(field)
        }
    }

    private static func bits(of set: some OptionSet) -> UInt64 {
        guard let raw = set.rawValue as? any BinaryInteger else { return 0 }
        return widen(raw)
    }

    private static func widen(_ number: some BinaryInteger) -> UInt64 {
        UInt64(truncatingIfNeeded: number)
    }

    /// The case of an enum value. A payload case names itself; a case with no payload
    /// prints its name, unless the type has a `description` of its own.
    private static func caseName(_ value: Any, mirror: Mirror) -> String? {
        if let payload = mirror.children.first, let label = payload.label {
            guard label == "unknown" else { return label }
            return firstInteger(in: payload.value).map { "unknown \($0)" } ?? label
        }
        if value is any CustomStringConvertible {
            return nil
        }
        return String(describing: value)
    }

    private static func firstInteger(in value: Any) -> UInt64? {
        if let number = value as? any BinaryInteger {
            return widen(number)
        }
        return Mirror(reflecting: value).children.lazy.compactMap { firstInteger(in: $0.value) }
            .first
    }

    private static func scalarCarries(_ value: Any) -> Bool? {
        switch value {
        case let flag as Bool: flag
        case let text as String: !text.isEmpty
        case let bytes as Data: !bytes.isEmpty
        case let number as any BinaryInteger: isNonZero(number)
        case let number as any BinaryFloatingPoint: isNonZero(number)
        default: nil
        }
    }

    private static func isNonZero(_ number: some BinaryInteger) -> Bool {
        number != 0
    }

    private static func isNonZero(_ number: some BinaryFloatingPoint) -> Bool {
        number != 0
    }

    /// The decode tally and property-wrapper or lazy storage are no fields of the record.
    private static func isField(_ label: String) -> Bool {
        label != "skipped" && !label.hasPrefix("_") && !label.hasPrefix("$")
    }

    /// `Weapon.CriticalData` for a type of the counted module, or nil.
    private mutating func typeName(of value: Any) -> String? {
        let type = Swift.type(of: value)
        if let known = typeNames[ObjectIdentifier(type)] {
            return known
        }
        var name: String? = String(reflecting: type)
        if let full = name, full.hasPrefix(module), !full.contains("(") {
            let local = full.dropFirst(module.count)
            name = String(local.prefix { $0 != "<" })
        } else {
            name = nil
        }
        typeNames[ObjectIdentifier(type)] = name
        return name
    }
}
