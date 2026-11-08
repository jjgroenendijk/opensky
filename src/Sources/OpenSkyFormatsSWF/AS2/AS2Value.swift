// ActionScript 2 value: the six ECMAScript types. Objects are `AS2Object`
// references; the rest are primitives. `SWF*` types parse bytes and `AS2*`
// types run bytecode; they share no type. Spec: ECMA-262 3rd ed. section 8.

import Foundation

/// One ActionScript 2 value.
nonisolated public enum AS2Value {
    case undefined
    case null
    case boolean(Bool)
    case number(Double)
    case string(String)
    case object(AS2Object)
}

nonisolated extension AS2Value {
    /// A number built from an integer, the form most opcodes produce.
    public static func integer(_ value: Int) -> AS2Value {
        .number(Double(value))
    }

    /// True for everything except `.object` — the ECMA-262 3rd edition
    /// "primitive value" set (section 4.3.2).
    public var isPrimitive: Bool {
        if case .object = self {
            return false
        }
        return true
    }

    /// The referenced object, or nil for a primitive.
    public var objectValue: AS2Object? {
        guard case let .object(object) = self else {
            return nil
        }
        return object
    }

    /// The referenced object when it is callable, else nil.
    public var functionValue: AS2Object? {
        guard let object = objectValue, object.isFunction else {
            return nil
        }
        return object
    }

    /// What `ActionTypeOf` (0x44) reports. ActionScript deviates from
    /// ECMAScript in two places: `typeof null` is `"null"` rather than
    /// `"object"`, and a display object reports its own name (`"movieclip"`),
    /// which an object carries in `AS2Object.typeOverride`.
    public var typeName: String {
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

nonisolated extension AS2Value: Equatable {
    /// Strict equality (`ActionStrictEquals`, 0x66): same type and same value,
    /// with objects compared by identity. NaN is unequal to itself and -0
    /// equals 0, both inherited from `Double`.
    ///
    /// Reference: ECMA-262 3rd edition, section 11.9.6 "The Strict Equality
    /// Comparison Algorithm".
    public static func == (left: AS2Value, right: AS2Value) -> Bool {
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
