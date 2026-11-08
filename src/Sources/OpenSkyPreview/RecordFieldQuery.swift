// `openskycli record find`: a decoded record as flat field paths, and the `--where`
// filters that match them. Pure, so the matching is unit-tested without game data.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// One leaf of a decoded record. Every element of a list shares the list's path.
nonisolated public struct RecordField: Equatable, Sendable {
    public let path: String
    public let value: String

    public init(path: String, value: String) {
        self.path = path
        self.value = value
    }
}

nonisolated public enum RecordFields {
    private static let depthCap = 8

    /// The leaves of a decoded value. A FormID reads through `resolve`; nil fields are left out.
    public static func flatten(_ value: Any, resolve: DecodedValueDump.Resolve) -> [RecordField] {
        var fields: [RecordField] = []
        append(value, path: "", depth: 0, resolve: resolve, into: &fields)
        return fields
    }

    private static func append(
        _ value: Any, path: String, depth: Int, resolve: DecodedValueDump.Resolve,
        into fields: inout [RecordField]
    ) {
        guard let value = DecodedValueDump.unwrapped(value) else { return }
        if let leaf = leafText(value, resolve: resolve) {
            fields.append(RecordField(path: path, value: leaf))
            return
        }
        let mirror = Mirror(reflecting: value)
        guard depth < depthCap else {
            fields.append(RecordField(path: path, value: String(describing: value)))
            return
        }
        let isList = [.collection, .set].contains(mirror.displayStyle)
        for (index, child) in mirror.children.enumerated() {
            let childPath = if isList {
                path
            } else {
                join(path, child.label ?? "\(index)")
            }
            append(child.value, path: childPath, depth: depth + 1, resolve: resolve, into: &fields)
        }
    }

    private static func join(_ path: String, _ label: String) -> String {
        path.isEmpty ? label : "\(path).\(label)"
    }

    private static func leafText(_ value: Any, resolve: DecodedValueDump.Resolve) -> String? {
        if let formID = value as? FormID {
            return resolve(formID)
        }
        if let string = value as? String {
            return string
        }
        if let data = value as? Data {
            return "\(data.count) bytes"
        }
        if
            Mirror(reflecting: value).children.isEmpty || value is FourCC || value is LString
            || DecodedValueDump.isSIMD(value)
        {
            return String(describing: value)
        }
        return nil
    }
}

/// `<field><op><value>`, or `<field>` alone for "has a value".
nonisolated public struct RecordFieldFilter: Equatable, Sendable {
    public enum Operator: String, CaseIterable, Sendable {
        // Two-character operators first, so `!=` is not read as `!` and `=`.
        case notEqual = "!=", notContains = "!~", lessOrEqual = "<=", greaterOrEqual = ">="
        case equal = "=", contains = "~", less = "<", greater = ">"
    }

    public let path: String
    /// Nil means the field only has to have a value.
    public let comparison: (operator: Operator, value: String)?

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let position = Self.firstOperator(in: trimmed)
        let path = position.map { String(trimmed[..<$0.1.lowerBound]) } ?? trimmed
        guard Self.isPath(path.trimmingCharacters(in: .whitespaces)) else { return nil }
        self.path = path.trimmingCharacters(in: .whitespaces)
        comparison = position.map { op, range in
            (op, String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces))
        }
    }

    /// The earliest operator; at one position the longer one, so `<=` wins over `<`.
    private static func firstOperator(in text: String) -> (Operator, Range<String.Index>)? {
        var best: (Operator, Range<String.Index>)?
        for op in Operator.allCases {
            guard let range = text.range(of: op.rawValue) else { continue }
            guard let current = best else {
                best = (op, range)
                continue
            }
            let earlier = range.lowerBound < current.1.lowerBound
            let longer = range.lowerBound == current.1.lowerBound
                && op.rawValue.count > current.0.rawValue.count
            if earlier || longer {
                best = (op, range)
            }
        }
        return best
    }

    public static func == (left: Self, right: Self) -> Bool {
        left.path == right.path && left.comparison?.operator == right.comparison?.operator
            && left.comparison?.value == right.comparison?.value
    }

    private static func isPath(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isLetter || $0.isNumber || "._".contains($0) }
    }

    /// The values of `fields` at `path`: an exact path, or a path that ends in it.
    public static func values(at path: String, in fields: [RecordField]) -> [String] {
        let wanted = path.lowercased()
        return fields.filter { field in
            let candidate = field.path.lowercased()
            return candidate == wanted || candidate.hasSuffix(".\(wanted)")
        }.map(\.value)
    }

    public func matches(_ fields: [RecordField]) -> Bool {
        let values = Self.values(at: path, in: fields)
        guard let comparison else { return !values.isEmpty }
        let target = comparison.value
        switch comparison.operator {
        case .equal: return values.contains { $0.caseInsensitiveCompare(target) == .orderedSame }
        case .notEqual: return !values
            .contains { $0.caseInsensitiveCompare(target) == .orderedSame }
        case .contains: return values.contains { $0.localizedCaseInsensitiveContains(target) }
        case .notContains: return !values.contains { $0.localizedCaseInsensitiveContains(target) }
        case .less, .lessOrEqual, .greater, .greaterOrEqual:
            guard let bound = Double(target) else { return false }
            return values.compactMap(Double.init).contains { compare($0, bound) }
        }
    }

    private func compare(_ value: Double, _ bound: Double) -> Bool {
        switch comparison?.operator {
        case .less: value < bound
        case .lessOrEqual: value <= bound
        case .greater: value > bound
        case .greaterOrEqual: value >= bound
        default: false
        }
    }
}
