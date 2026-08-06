// ActionScript 2 primitive coercions (milestone 8.3.2). Everything here works
// on values that are already primitive; `ToPrimitive` needs to call `valueOf`
// and `toString`, so it lives on the interpreter (`AS2InterpreterCoercion`)
// and hands the result back down to these routines.
//
// Two rules depend on the movie's SWF version, which is why this is a value
// with a `swfVersion` rather than a namespace of static functions:
// string-to-boolean and the string form of `undefined` both changed in SWF 7.
//
// Reference: ECMA-262 3rd edition, section 9 "Type Conversion and Testing" —
// 9.2 "ToBoolean", 9.3 "ToNumber" (9.3.1 for the string grammar), 9.5
// "ToInt32", 9.6 "ToUint32", 9.8 "ToString" (9.8.1 for numbers), and section
// 11.9.3 "The Abstract Equality Comparison Algorithm" plus 11.8.5 "The
// Abstract Relational Comparison Algorithm".

import Foundation

nonisolated struct AS2Coercion {
    /// The SWF version of the movie whose bytecode is running.
    let swfVersion: UInt8

    /// Vanilla Skyrim menus are published well past SWF 7, so the ECMAScript
    /// rules apply unless a caller says otherwise.
    static let latest = AS2Coercion(swfVersion: 9)

    /// The version from which Flash adopted the ECMAScript string rules.
    static let ecmaStringVersion: UInt8 = 7

    private var usesECMAStrings: Bool {
        swfVersion >= AS2Coercion.ecmaStringVersion
    }

    // MARK: - ToBoolean

    func toBoolean(_ value: AS2Value) -> Bool {
        switch value {
        case .undefined, .null:
            false
        case let .boolean(flag):
            flag
        case let .number(number):
            number != 0 && !number.isNaN
        case let .string(text):
            usesECMAStrings ? !text.isEmpty : isTruthyNumericString(text)
        case .object:
            true
        }
    }

    /// The SWF 6 and earlier rule: a string is true when it reads as a non-zero
    /// number. An unparseable string reads as NaN, which is false.
    private func isTruthyNumericString(_ text: String) -> Bool {
        let number = stringToNumber(text)
        return number != 0 && !number.isNaN
    }

    // MARK: - ToNumber

    /// Objects reach this only when `ToPrimitive` produced no primitive, which
    /// ECMA-262 treats as a `TypeError`; ActionScript has no exception here and
    /// yields NaN instead.
    func toNumber(_ value: AS2Value) -> Double {
        switch value {
        case .undefined:
            usesECMAStrings ? Double.nan : 0
        case .null:
            0
        case let .boolean(flag):
            flag ? 1 : 0
        case let .number(number):
            number
        case let .string(text):
            stringToNumber(text)
        case .object:
            Double.nan
        }
    }

    /// ECMA-262 3rd edition 9.3.1 "ToNumber Applied to the String Type", plus
    /// the `0x` hexadecimal form ActionScript accepts.
    func stringToNumber(_ text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 0
        }
        var body = Substring(trimmed)
        var negative = false
        if body.hasPrefix("+") {
            body = body.dropFirst()
        } else if body.hasPrefix("-") {
            negative = true
            body = body.dropFirst()
        }
        if body == "Infinity" {
            return negative ? -.infinity : .infinity
        }
        if let hex = AS2Coercion.hexadecimalValue(body) {
            return negative ? -hex : hex
        }
        guard AS2Coercion.isDecimalLiteral(body), let magnitude = Double(body) else {
            return .nan
        }
        return negative ? -magnitude : magnitude
    }

    // MARK: - ToString

    func toString(_ value: AS2Value) -> String {
        switch value {
        case .undefined:
            usesECMAStrings ? "undefined" : ""
        case .null:
            "null"
        case let .boolean(flag):
            flag ? "true" : "false"
        case let .number(number):
            AS2Coercion.numberToString(number)
        case let .string(text):
            text
        case let .object(object):
            object.isFunction ? "[type Function]" : "[object Object]"
        }
    }

    // MARK: - Comparison

    /// `ActionEquals2` (0x49). Both arguments must already be primitive.
    func equals(_ left: AS2Value, _ right: AS2Value) -> Bool {
        switch (left, right) {
        case (.undefined, .undefined), (.null, .null),
             (.undefined, .null), (.null, .undefined):
            return true
        case (.undefined, _), (_, .undefined), (.null, _), (_, .null):
            return false
        default:
            break
        }
        if case let .string(lhs) = left, case let .string(rhs) = right {
            return lhs == rhs
        }
        if case let .object(lhs) = left, case let .object(rhs) = right {
            return lhs === rhs
        }
        return toNumber(left) == toNumber(right)
    }

    /// `ActionLess2` (0x48) — and `ActionGreater` (0x67) with the operands
    /// swapped. Both arguments must already be primitive. An undefined
    /// comparison result (either side NaN) is reported as false, which is what
    /// both opcodes push.
    func lessThan(_ left: AS2Value, _ right: AS2Value) -> Bool {
        if case let .string(lhs) = left, case let .string(rhs) = right {
            return lhs.utf16.lexicographicallyPrecedes(rhs.utf16)
        }
        let lhs = toNumber(left)
        let rhs = toNumber(right)
        if lhs.isNaN || rhs.isNaN {
            return false
        }
        return lhs < rhs
    }
}
