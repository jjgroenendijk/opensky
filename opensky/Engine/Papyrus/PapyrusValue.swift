// Runtime values and type names for the Skyrim Papyrus virtual machine.
//
// Reference: Creation Kit wiki, "Literals Reference", "Cast Reference", and
// "Arrays (Papyrus)". Skyrim Papyrus has scalar values, opaque object
// references, and one-dimensional arrays. Fallout 4 structs are deliberately
// not represented here.

import Foundation

nonisolated struct PapyrusObjectHandle: Equatable, Hashable, Sendable {
    let rawValue: UInt64

    init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

indirect nonisolated enum PapyrusType: Equatable, Sendable {
    case none
    case boolean
    case integer
    case float
    case string
    case object(String)
    case array(PapyrusType)

    init(name: String) {
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

    var name: String {
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

    var defaultValue: PapyrusValue {
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

nonisolated final class PapyrusArray: @unchecked Sendable {
    let elementType: PapyrusType
    var elements: [PapyrusValue]

    init(elementType: PapyrusType, elements: [PapyrusValue]) {
        self.elementType = elementType
        self.elements = elements
    }
}

nonisolated enum PapyrusValue: Sendable {
    case none
    case boolean(Bool)
    case integer(Int32)
    case float(Float)
    case string(String)
    case object(PapyrusObjectHandle)
    case array(PapyrusArray)

    var typeName: String {
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
    static func == (left: PapyrusValue, right: PapyrusValue) -> Bool {
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
