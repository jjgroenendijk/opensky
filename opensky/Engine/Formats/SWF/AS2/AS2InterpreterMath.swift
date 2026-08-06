// Arithmetic, comparison, and bitwise opcodes (milestone 8.3.2).
//
// Every one of these pops its right operand first, because the compiler pushes
// left then right. Getting that backwards is invisible for `+` on numbers and
// wrong for everything else, so the order is spelled out at each site.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — "ActionAdd2", "ActionLess2", "ActionEquals2" (pp. 96-99),
// "ActionSubtract", "ActionMultiply", "ActionDivide" (pp. 71-72),
// "ActionModulo" (p. 87), the bitwise actions (pp. 100-102), and
// "ActionIncrement"/"ActionDecrement" (p. 103). Semantics follow ECMA-262 3rd
// edition sections 11.6 "Additive Operators", 11.7 "Bitwise Shift Operators",
// 11.8 "Relational Operators", 11.9 "Equality Operators", and 11.10 "Binary
// Bitwise Operators".

import Foundation

nonisolated extension AS2Interpreter {
    func arithmeticOp(_ record: SWFActionRecord, frame: AS2Frame) throws(AS2Fault) -> AS2Flow? {
        switch record.code {
        case AS2Opcode.subtract:
            try applyBinaryNumbers(frame) { $0 - $1 }
        case AS2Opcode.multiply:
            try applyBinaryNumbers(frame) { $0 * $1 }
        case AS2Opcode.divide:
            try applyBinaryNumbers(frame) { $0 / $1 }
        case AS2Opcode.modulo:
            try applyBinaryNumbers(frame) { $0.truncatingRemainder(dividingBy: $1) }
        case AS2Opcode.add2:
            try add2(frame)
        case AS2Opcode.increment:
            try applyUnaryNumber(frame) { $0 + 1 }
        case AS2Opcode.decrement:
            try applyUnaryNumber(frame) { $0 - 1 }
        case AS2Opcode.toNumber:
            try applyUnaryNumber(frame) { $0 }
        case AS2Opcode.toString:
            let text = try toString(frame.pop())
            try frame.push(.string(text))
        default:
            return nil
        }
        return .next
    }

    /// ECMA-262 11.6.1: both operands become primitives first, and a string on
    /// either side makes the operator a concatenation.
    private func add2(_ frame: AS2Frame) throws(AS2Fault) {
        let right = try toPrimitive(frame.pop())
        let left = try toPrimitive(frame.pop())
        if case .string = left {
            try frame.push(.string(coercion.toString(left) + coercion.toString(right)))
            return
        }
        if case .string = right {
            try frame.push(.string(coercion.toString(left) + coercion.toString(right)))
            return
        }
        try frame.push(.number(coercion.toNumber(left) + coercion.toNumber(right)))
    }

    private func applyBinaryNumbers(
        _ frame: AS2Frame,
        _ operation: (Double, Double) -> Double
    ) throws(AS2Fault) {
        let right = try toNumber(frame.pop())
        let left = try toNumber(frame.pop())
        try frame.push(.number(operation(left, right)))
    }

    private func applyUnaryNumber(
        _ frame: AS2Frame,
        _ operation: (Double) -> Double
    ) throws(AS2Fault) {
        let value = try toNumber(frame.pop())
        try frame.push(.number(operation(value)))
    }
}

nonisolated extension AS2Interpreter {
    func comparisonOp(_ record: SWFActionRecord, frame: AS2Frame) throws(AS2Fault) -> AS2Flow? {
        switch record.code {
        case AS2Opcode.not:
            let value = frame.pop()
            try frame.push(.boolean(!toBoolean(value)))
        case AS2Opcode.equals2:
            let right = frame.pop()
            let left = frame.pop()
            try frame.push(.boolean(abstractEquals(left, right)))
        case AS2Opcode.strictEquals:
            let right = frame.pop()
            let left = frame.pop()
            try frame.push(.boolean(left == right))
        case AS2Opcode.less2:
            let right = frame.pop()
            let left = frame.pop()
            try frame.push(.boolean(abstractLessThan(left, right)))
        case AS2Opcode.greater:
            let right = frame.pop()
            let left = frame.pop()
            try frame.push(.boolean(abstractLessThan(right, left)))
        default:
            return nil
        }
        return .next
    }

    func bitwiseOp(_ record: SWFActionRecord, frame: AS2Frame) throws(AS2Fault) -> AS2Flow? {
        switch record.code {
        case AS2Opcode.bitAnd:
            try applyBitwise(frame) { $0 & $1 }
        case AS2Opcode.bitOr:
            try applyBitwise(frame) { $0 | $1 }
        case AS2Opcode.bitXor:
            try applyBitwise(frame) { $0 ^ $1 }
        case AS2Opcode.bitLShift:
            try applyShift(frame) { Double(Int32(truncatingIfNeeded: Int64($0) << $1)) }
        case AS2Opcode.bitRShift:
            try applyShift(frame) { Double($0 >> $1) }
        case AS2Opcode.bitURShift:
            try applyShift(frame) { Double(UInt32(bitPattern: $0) >> UInt32($1)) }
        default:
            return nil
        }
        return .next
    }

    private func applyBitwise(
        _ frame: AS2Frame,
        _ operation: (Int32, Int32) -> Int32
    ) throws(AS2Fault) {
        let right = try AS2Coercion.toInt32(toNumber(frame.pop()))
        let left = try AS2Coercion.toInt32(toNumber(frame.pop()))
        try frame.push(.number(Double(operation(left, right))))
    }

    /// The shift count is the low five bits of the right operand (ECMA-262
    /// 11.7.1), so a shift can never be undefined behavior.
    private func applyShift(
        _ frame: AS2Frame,
        _ operation: (Int32, Int32) -> Double
    ) throws(AS2Fault) {
        let count = try AS2Coercion.toUInt32(toNumber(frame.pop())) & 0x1F
        let left = try AS2Coercion.toInt32(toNumber(frame.pop()))
        try frame.push(.number(operation(left, Int32(count))))
    }
}
