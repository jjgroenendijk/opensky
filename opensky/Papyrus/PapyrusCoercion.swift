// Papyrus primitive conversion rules.
//
// The public language reference defines truthiness and the supported cast
// directions but does not specify every failed parse. This layer returns a
// typed conversion error so the interpreter can fault without trapping.

import Foundation

nonisolated enum PapyrusCoercionError: Error, Equatable {
    case unsupported(source: String, destination: String)
    case invalidNumber(String)
}

nonisolated struct PapyrusCoercion {
    func toBoolean(_ value: PapyrusValue) -> Bool {
        switch value {
        case .none:
            false
        case let .boolean(value):
            value
        case let .integer(value):
            value != 0
        case let .float(value):
            value != 0 && !value.isNaN
        case let .string(value):
            !value.isEmpty
        case .object:
            true
        case let .array(array):
            !array.elements.isEmpty
        }
    }

    func toInteger(_ value: PapyrusValue) throws(PapyrusCoercionError) -> Int32 {
        switch value {
        case let .integer(value):
            value
        case let .float(value):
            try integer(from: value)
        case let .boolean(value):
            value ? 1 : 0
        case let .string(value):
            try parseInteger(value)
        default:
            throw .unsupported(source: value.typeName, destination: "Int")
        }
    }

    func toFloat(_ value: PapyrusValue) throws(PapyrusCoercionError) -> Float {
        switch value {
        case let .float(value):
            return value
        case let .integer(value):
            return Float(value)
        case let .boolean(value):
            return value ? 1 : 0
        case let .string(value):
            guard let parsed = Float(value.trimmingCharacters(in: .whitespaces)) else {
                throw .invalidNumber(value)
            }
            return parsed
        default:
            throw .unsupported(source: value.typeName, destination: "Float")
        }
    }

    func toString(_ value: PapyrusValue) -> String {
        switch value {
        case .none:
            "None"
        case let .boolean(value):
            value ? "True" : "False"
        case let .integer(value):
            String(value)
        case let .float(value):
            String(value)
        case let .string(value):
            value
        case let .object(handle):
            "[Object \(handle.rawValue)]"
        case let .array(array):
            "[\(array.elementType.name) array \(array.elements.count)]"
        }
    }

    private func parseInteger(_ value: String) throws(PapyrusCoercionError) -> Int32 {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if
            trimmed.lowercased().hasPrefix("0x"),
            let parsed = UInt32(trimmed.dropFirst(2), radix: 16)
        {
            return Int32(bitPattern: parsed)
        }
        if let parsed = Int32(trimmed) {
            return parsed
        }
        if let parsed = Float(trimmed), parsed.isFinite {
            return try integer(from: parsed)
        }
        throw .invalidNumber(value)
    }

    private func integer(from value: Float) throws(PapyrusCoercionError) -> Int32 {
        guard value.isFinite else {
            throw .invalidNumber(String(value))
        }
        if value >= Float(Int32.max) {
            return .max
        }
        if value <= Float(Int32.min) {
            return .min
        }
        return Int32(value.rounded(.towardZero))
    }
}
