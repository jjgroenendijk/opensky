// Runtime values and type names for the Skyrim Papyrus virtual machine.
//
// Reference: Creation Kit wiki, "Literals Reference", "Cast Reference", and
// "Arrays (Papyrus)". Skyrim Papyrus has scalar values, opaque object
// references, and one-dimensional arrays. Fallout 4 structs are deliberately
// not represented here.

import Foundation
import Synchronization

nonisolated public struct PapyrusObjectHandle: Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

indirect nonisolated public enum PapyrusType: Equatable, Sendable {
    case none
    case boolean
    case integer
    case float
    case string
    case object(String)
    case array(PapyrusType)

    public init(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("[]") {
            self = .array(PapyrusType(name: String(trimmed.dropLast(2))))
            return
        }
        switch trimmed.lowercased() {
        case "", "none":
            self = .none
        case "bool":
            self = .boolean
        case "int":
            self = .integer
        case "float":
            self = .float
        case "string":
            self = .string
        default:
            self = .object(trimmed)
        }
    }

    public var name: String {
        switch self {
        case .none: "None"
        case .boolean: "Bool"
        case .integer: "Int"
        case .float: "Float"
        case .string: "String"
        case let .object(name): name
        case let .array(element): "\(element.name)[]"
        }
    }

    public var defaultValue: PapyrusValue {
        switch self {
        case .none, .object, .array:
            .none
        case .boolean:
            .boolean(false)
        case .integer:
            .integer(0)
        case .float:
            .float(0)
        case .string:
            .string("")
        }
    }
}

/// A Papyrus array has reference semantics: every copy of the value sees a write.
nonisolated public final class PapyrusArray: Sendable {
    public let elementType: PapyrusType
    private let storage: Mutex<[PapyrusValue]>

    public init(elementType: PapyrusType, elements: [PapyrusValue]) {
        self.elementType = elementType
        storage = Mutex(elements)
    }

    /// A snapshot. Later writes do not change it.
    public var elements: [PapyrusValue] {
        storage.withLock { $0 }
    }

    public var count: Int {
        storage.withLock { $0.count }
    }

    /// Writes in place. The index must be in bounds.
    public func setElement(_ value: PapyrusValue, at index: Int) {
        storage.withLock { $0[index] = value }
    }
}

nonisolated public enum PapyrusValue: Sendable {
    case none
    case boolean(Bool)
    case integer(Int32)
    case float(Float)
    case string(String)
    case object(PapyrusObjectHandle)
    case array(PapyrusArray)

    public var typeName: String {
        switch self {
        case .none: "None"
        case .boolean: "Bool"
        case .integer: "Int"
        case .float: "Float"
        case .string: "String"
        case .object: "Object"
        case let .array(array): "\(array.elementType.name)[]"
        }
    }
}

nonisolated extension PapyrusValue: Equatable {
    public static func == (left: PapyrusValue, right: PapyrusValue) -> Bool {
        switch (left, right) {
        case (.none, .none):
            true
        case let (.boolean(leftValue), .boolean(rightValue)):
            leftValue == rightValue
        case let (.integer(leftValue), .integer(rightValue)):
            leftValue == rightValue
        case let (.float(leftValue), .float(rightValue)):
            leftValue == rightValue
        case let (.string(leftValue), .string(rightValue)):
            leftValue.caseInsensitiveCompare(rightValue) == .orderedSame
        case let (.object(leftValue), .object(rightValue)):
            leftValue == rightValue
        case let (.array(leftValue), .array(rightValue)):
            leftValue === rightValue
        default:
            false
        }
    }
}
