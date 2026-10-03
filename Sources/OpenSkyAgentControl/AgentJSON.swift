// A JSON value with no schema, for request arguments and reply results. Each
// command reads and writes a small, documented shape (docs/tools/agent-control.md).

import Foundation

nonisolated public enum AgentJSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AgentJSON])
    case object([String: AgentJSON])

    public subscript(key: String) -> AgentJSON? {
        guard case let .object(fields) = self else { return nil }
        return fields[key]
    }

    public var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case let .number(value): value
        case let .string(text): Double(text)
        default: nil
        }
    }

    /// A whole number. A fraction or a value outside `Int` is not one.
    public var intValue: Int? {
        guard let value = doubleValue, value.rounded() == value, abs(value) < 1e15 else {
            return nil
        }
        return Int(value)
    }

    public var boolValue: Bool? {
        switch self {
        case let .bool(value): value
        case let .string(text): ["true", "1", "yes"].contains(text.lowercased())
        default: nil
        }
    }

    public var arrayValue: [AgentJSON]? {
        if case let .array(values) = self {
            return values
        }
        return nil
    }

    public var objectValue: [String: AgentJSON]? {
        if case let .object(fields) = self {
            return fields
        }
        return nil
    }

    /// Follows a dotted path such as `menu.top` or `actors.0.formID`.
    public func value(atPath path: String) -> AgentJSON? {
        var current: AgentJSON? = self
        for part in path.split(separator: ".").map(String.init) {
            switch current {
            case let .object(fields)?:
                current = fields[part]
            case let .array(values)?:
                guard let index = Int(part), values.indices.contains(index) else { return nil }
                current = values[index]
            default:
                return nil
            }
        }
        return current
    }
}

nonisolated extension AgentJSON {
    public init(_ value: Float) {
        self = .number(Double(value))
    }

    public init(_ value: Int) {
        self = .number(Double(value))
    }

    public init(_ value: String?) {
        self = value.map(AgentJSON.string) ?? .null
    }

    public init(_ vector: SIMD3<Float>) {
        self = .array([.init(vector.x), .init(vector.y), .init(vector.z)])
    }

    /// A FormID as the console writes it: eight upper-case hex digits.
    public static func formID(_ raw: UInt32) -> AgentJSON {
        .string(String(format: "%08X", raw))
    }
}

nonisolated extension AgentJSON: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AgentJSON].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: AgentJSON].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value.isFinite ? value : 0)
        case let .string(value): try container.encode(value)
        case let .array(values): try container.encode(values)
        case let .object(fields): try container.encode(fields)
        }
    }
}

nonisolated extension AgentJSON: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral
{
    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }

    public init(dictionaryLiteral elements: (String, AgentJSON)...) {
        self = .object(Dictionary(elements) { _, last in last })
    }

    public init(arrayLiteral elements: AgentJSON...) {
        self = .array(elements)
    }

    public init(integerLiteral value: Int) {
        self = .number(Double(value))
    }

    public init(floatLiteral value: Double) {
        self = .number(value)
    }
}
