// ActionScript 2 value model (milestone 8.3.2): the six value types the AS2
// interpreter manipulates. Objects are reference types (`AS2Object`); every
// other case is a primitive carried by value, matching ECMAScript.
//
// The `AS2` prefix rather than `SWF` marks the boundary: everything named
// `SWF*` in this directory tree parses bytes off disk, while `AS2*` executes
// the bytecode those parsers framed. The two never share a type.
//
// Reference: ECMA-262 3rd edition, section 8 "Types" — Undefined (8.1), Null
// (8.2), Boolean (8.3), Number (8.5), String (8.4), and Object (8.6).
// ActionScript 2 adds no value type of its own: `MovieClip`, `TextField` and
// the rest are ordinary objects.

import Foundation

/// One ActionScript 2 value.
nonisolated enum AS2Value {
    case undefined
    case null
    case boolean(Bool)
    case number(Double)
    case string(String)
    case object(AS2Object)
}

extension AS2Value {
    /// A number built from an integer, the form most opcodes produce.
    static func integer(_ value: Int) -> AS2Value {
        .number(Double(value))
    }

    /// True for everything except `.object` — the ECMA-262 3rd edition
    /// "primitive value" set (section 4.3.2).
    var isPrimitive: Bool {
        if case .object = self {
            return false
        }
        return true
    }

    /// The referenced object, or nil for a primitive.
    var objectValue: AS2Object? {
        guard case let .object(object) = self else {
            return nil
        }
        return object
    }

    /// The referenced object when it is callable, else nil.
    var functionValue: AS2Object? {
        guard let object = objectValue, object.isFunction else {
            return nil
        }
        return object
    }

    /// What `ActionTypeOf` (0x44) reports. ActionScript deviates from
    /// ECMAScript in two places: `typeof null` is `"null"` rather than
    /// `"object"`, and a display object reports its own name (`"movieclip"`),
    /// which an object carries in `AS2Object.typeOverride`.
    var typeName: String {
        switch self {
        case .undefined: "undefined"
        case .null: "null"
        case .boolean: "boolean"
        case .number: "number"
        case .string: "string"
        case let .object(object): object.typeName
        }
    }
}

extension AS2Value: Equatable {
    /// Strict equality (`ActionStrictEquals`, 0x66): same type and same value,
    /// with objects compared by identity. NaN is unequal to itself and -0
    /// equals 0, both inherited from `Double`.
    ///
    /// Reference: ECMA-262 3rd edition, section 11.9.6 "The Strict Equality
    /// Comparison Algorithm".
    static func == (left: AS2Value, right: AS2Value) -> Bool {
        switch (left, right) {
        case (.undefined, .undefined), (.null, .null):
            true
        case let (.boolean(lhs), .boolean(rhs)):
            lhs == rhs
        case let (.number(lhs), .number(rhs)):
            lhs == rhs
        case let (.string(lhs), .string(rhs)):
            lhs == rhs
        case let (.object(lhs), .object(rhs)):
            lhs === rhs
        default:
            false
        }
    }
}
