// Object-aware coercions: `ToPrimitive` calls `valueOf`, then `toString`, which
// needs an execution context. Spec: ECMA-262 3rd ed. sections 8.6.2.6, 9.1,
// and 11.9.3.

import Foundation

/// Which conversion an object is asked for first.
nonisolated public enum AS2PrimitiveHint: Sendable {
    case number
    case string
}

nonisolated extension AS2Interpreter {
    /// ECMA-262 9.1. A plain object with neither usable method degrades to its
    /// string form rather than raising a `TypeError`, because ActionScript 2
    /// has no exception to raise here.
    public func toPrimitive(
        _ value: AS2Value,
        hint: AS2PrimitiveHint = .number
    ) throws(AS2Fault) -> AS2Value {
        guard value.objectValue != nil else {
            return value
        }
        let names = hint == .string ? ["toString", "valueOf"] : ["valueOf", "toString"]
        for name in names {
            guard let method = try getMember(name, of: value, offset: 0).functionValue else {
                continue
            }
            let result = try call(method, thisValue: value, arguments: [], offset: 0)
            if result.isPrimitive {
                return result
            }
        }
        return .string(coercion.toString(value))
    }

    public func toNumber(_ value: AS2Value) throws(AS2Fault) -> Double {
        try coercion.toNumber(toPrimitive(value, hint: .number))
    }

    public func toString(_ value: AS2Value) throws(AS2Fault) -> String {
        try coercion.toString(toPrimitive(value, hint: .string))
    }

    /// No object conversion is involved: every object is true.
    public func toBoolean(_ value: AS2Value) -> Bool {
        coercion.toBoolean(value)
    }

    /// The operand count an opcode popped, clamped so malformed bytecode cannot
    /// ask for a billion arguments.
    public func toArgumentCount(_ value: AS2Value) throws(AS2Fault) -> Int {
        let count = try toNumber(value)
        guard count.isFinite, count > 0 else {
            return 0
        }
        return min(Int(count), limits.stackDepth)
    }

    /// `ActionEquals2` (0x49).
    public func abstractEquals(_ left: AS2Value, _ right: AS2Value) throws(AS2Fault) -> Bool {
        if left.isPrimitive == right.isPrimitive {
            return coercion.equals(left, right)
        }
        return try coercion.equals(toPrimitive(left), toPrimitive(right))
    }

    /// `ActionLess2` (0x48), and `ActionGreater` (0x67) with the arguments
    /// swapped.
    public func abstractLessThan(_ left: AS2Value, _ right: AS2Value) throws(AS2Fault) -> Bool {
        try coercion.lessThan(toPrimitive(left), toPrimitive(right))
    }
}
