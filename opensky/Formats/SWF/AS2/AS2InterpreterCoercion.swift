// Object-aware coercions (milestone 8.3.2). `AS2Coercion` handles primitives;
// `ToPrimitive` has to call `valueOf` and `toString` on an object, which needs
// an execution context, so it lives here.
//
// Reference: ECMA-262 3rd edition, section 9.1 "ToPrimitive" and section 8.6.2.6
// "[[DefaultValue]] (hint)" for the valueOf-then-toString order, and section
// 11.9.3 "The Abstract Equality Comparison Algorithm" for the object case.

import Foundation

/// Which conversion an object is asked for first.
nonisolated enum AS2PrimitiveHint {
    case number
    case string
}

extension AS2Interpreter {
    /// ECMA-262 9.1. A plain object with neither usable method degrades to its
    /// string form rather than raising a `TypeError`, because ActionScript 2
    /// has no exception to raise here.
    func toPrimitive(
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

    func toNumber(_ value: AS2Value) throws(AS2Fault) -> Double {
        try coercion.toNumber(toPrimitive(value, hint: .number))
    }

    func toString(_ value: AS2Value) throws(AS2Fault) -> String {
        try coercion.toString(toPrimitive(value, hint: .string))
    }

    /// No object conversion is involved: every object is true.
    func toBoolean(_ value: AS2Value) -> Bool {
        coercion.toBoolean(value)
    }

    /// The operand count an opcode popped, clamped so malformed bytecode cannot
    /// ask for a billion arguments.
    func toArgumentCount(_ value: AS2Value) throws(AS2Fault) -> Int {
        let count = try toNumber(value)
        guard count.isFinite, count > 0 else {
            return 0
        }
        return min(Int(count), limits.stackDepth)
    }

    /// `ActionEquals2` (0x49).
    func abstractEquals(_ left: AS2Value, _ right: AS2Value) throws(AS2Fault) -> Bool {
        if left.isPrimitive == right.isPrimitive {
            return coercion.equals(left, right)
        }
        return try coercion.equals(toPrimitive(left), toPrimitive(right))
    }

    /// `ActionLess2` (0x48), and `ActionGreater` (0x67) with the arguments
    /// swapped.
    func abstractLessThan(_ left: AS2Value, _ right: AS2Value) throws(AS2Fault) -> Bool {
        try coercion.lessThan(toPrimitive(left), toPrimitive(right))
    }
}
