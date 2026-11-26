// Counts, per stored field of the decoded record types, the records that carry a value in
// it, so the gap report can rank the fields no engine code reads (docs/tools/gaps.md).
// It reads the values through reflection, so a new field is counted with no edit here.

import Foundation
public import OpenSkyFormatsCore

nonisolated public struct RecordFieldCensus: Sendable {
    public struct Field: Sendable, Equatable {
        /// Records with a value in the field.
        public var records = 0
        /// The same count per record type, as one Swift type can decode several.
        public var recordTypes: [FourCC: Int] = [:]
    }

    /// Fields keyed `Type.Nested.field`, as `tools/lint-index/record-field-reads.py` writes them.
    public private(set) var fields: [String: Field] = [:]
    /// Only types of this module have fields to count; others, such as `FormID`, are values.
    private let module: String
    private var typeNames: [ObjectIdentifier: String?] = [:]

    public init(module: String = "OpenSkyFormatsESM") {
        self.module = module + "."
    }

    /// Counts the fields `value` fills, each once per record however many entries hold it.
    public mutating func record(_ value: Any, type: FourCC) {
        var found = Set<String>()
        _ = visit(value, found: &found)
        for key in found {
            fields[key, default: Field()].records += 1
            fields[key, default: Field()].recordTypes[type, default: 0] += 1
        }
    }

    /// Records whether `value` carries a value: a present optional, a non-empty list or text,
    /// a non-zero number, a true flag, any enum case, or a struct with such a field.
    private mutating func visit(_ value: Any, found: inout Set<String>) -> Bool {
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
                    found.insert("\(owner).\(label)")
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
