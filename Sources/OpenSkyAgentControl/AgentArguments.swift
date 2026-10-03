// Typed reads of a request's named arguments. A missing or wrong-typed value
// becomes an `invalidArgument` reply, never a crash.

import Foundation

nonisolated public struct AgentArguments: Sendable {
    public let command: String
    public let values: [String: AgentJSON]

    public init(command: String, values: [String: AgentJSON]) {
        self.command = command
        self.values = values
    }

    public func has(_ name: String) -> Bool {
        values[name].map { $0 != .null } ?? false
    }

    public func string(_ name: String) throws(AgentFailure) -> String {
        guard let value = values[name] else { throw missing(name) }
        switch value {
        case let .string(text) where !text.isEmpty: return text
        case let .number(number): return String(Int(number))
        default: throw invalid(name, "a non-empty string")
        }
    }

    public func optionalString(_ name: String) throws(AgentFailure) -> String? {
        has(name) ? try string(name) : nil
    }

    public func int(_ name: String) throws(AgentFailure) -> Int {
        guard let value = values[name] else { throw missing(name) }
        guard let number = value.intValue else { throw invalid(name, "a whole number") }
        return number
    }

    public func optionalInt(_ name: String) throws(AgentFailure) -> Int? {
        has(name) ? try int(name) : nil
    }

    public func float(_ name: String) throws(AgentFailure) -> Float {
        guard let value = values[name] else { throw missing(name) }
        guard let number = value.doubleValue, number.isFinite else {
            throw invalid(name, "a number")
        }
        return Float(number)
    }

    public func optionalFloat(_ name: String) throws(AgentFailure) -> Float? {
        has(name) ? try float(name) : nil
    }

    public func bool(_ name: String, default fallback: Bool) throws(AgentFailure) -> Bool {
        guard has(name), let value = values[name] else { return fallback }
        guard let flag = value.boolValue else { throw invalid(name, "true or false") }
        return flag
    }

    /// A list given as a JSON array or as one comma-separated string.
    public func list(_ name: String) throws(AgentFailure) -> [String] {
        guard has(name), let value = values[name] else { return [] }
        switch value {
        case let .string(text):
            return text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        case let .array(items):
            let strings = items.compactMap(\.stringValue)
            guard strings.count == items.count else { throw invalid(name, "a list of names") }
            return strings
        default:
            throw invalid(name, "a list of names")
        }
    }

    /// A position given as `[x, y, z]` or as `"x,y,z"`.
    public func vector(_ name: String) throws(AgentFailure) -> SIMD3<Float> {
        guard let value = values[name] else { throw missing(name) }
        let parts: [Double?] = switch value {
        case let .array(items): items.map(\.doubleValue)
        case let .string(text):
            text.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        default: []
        }
        let numbers = parts.compactMap(\.self)
        guard parts.count == 3, numbers.count == 3, numbers.allSatisfy(\.isFinite) else {
            throw invalid(name, "three numbers x,y,z")
        }
        return SIMD3(Float(numbers[0]), Float(numbers[1]), Float(numbers[2]))
    }

    public func invalid(_ name: String, _ expected: String) -> AgentFailure {
        AgentFailure(.invalidArgument, "\(command): \(name) must be \(expected)")
    }

    private func missing(_ name: String) -> AgentFailure {
        AgentFailure(.invalidArgument, "\(command): missing \(name)")
    }
}
