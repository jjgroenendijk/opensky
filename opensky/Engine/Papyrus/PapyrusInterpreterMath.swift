// Integer, floating-point, string, and comparison opcodes.

import Foundation

nonisolated extension PapyrusInterpreter {
    func mathOp(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow? {
        if let flow = try integerMathOp(instruction, frame: frame) {
            return flow
        }
        if let flow = try floatMathOp(instruction, frame: frame) {
            return flow
        }
        switch instruction.opcode {
        case .not:
            let operands = try requireOperands(2, instruction: instruction)
            let value = try read(operands[1], frame: frame)
            try write(
                .boolean(!runtime.coercion.toBoolean(value)),
                to: operands[0],
                frame: frame
            )
            return .next
        case .stringConcatenate:
            let operands = try requireOperands(3, instruction: instruction)
            let left = try runtime.coercion.toString(read(operands[1], frame: frame))
            let right = try runtime.coercion.toString(read(operands[2], frame: frame))
            try write(.string(left + right), to: operands[0], frame: frame)
            return .next
        default:
            return nil
        }
    }

    private func integerMathOp(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow? {
        switch instruction.opcode {
        case .integerAdd:
            return try integerBinary(instruction, frame: frame, operation: &+)
        case .integerSubtract:
            return try integerBinary(instruction, frame: frame, operation: &-)
        case .integerMultiply:
            return try integerBinary(instruction, frame: frame, operation: &*)
        case .integerDivide:
            return try integerDivision(instruction, frame: frame, modulo: false)
        case .integerModulo:
            return try integerDivision(instruction, frame: frame, modulo: true)
        case .integerNegate:
            let operands = try requireOperands(2, instruction: instruction)
            let value = try integer(operands[1], frame: frame)
            try write(.integer(0 &- value), to: operands[0], frame: frame)
            return .next
        default:
            return nil
        }
    }

    private func floatMathOp(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow? {
        switch instruction.opcode {
        case .floatAdd:
            return try floatBinary(instruction, frame: frame, operation: +)
        case .floatSubtract:
            return try floatBinary(instruction, frame: frame, operation: -)
        case .floatMultiply:
            return try floatBinary(instruction, frame: frame, operation: *)
        case .floatDivide:
            return try floatDivision(instruction, frame: frame)
        case .floatNegate:
            let operands = try requireOperands(2, instruction: instruction)
            try write(
                .float(-float(operands[1], frame: frame)),
                to: operands[0],
                frame: frame
            )
            return .next
        default:
            return nil
        }
    }

    func comparisonOp(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow? {
        switch instruction.opcode {
        case .compareEqual:
            let operands = try requireOperands(3, instruction: instruction)
            let left = try read(operands[1], frame: frame)
            let right = try read(operands[2], frame: frame)
            try write(.boolean(equal(left, right)), to: operands[0], frame: frame)
            return .next
        case .compareLess, .compareLessOrEqual, .compareGreater, .compareGreaterOrEqual:
            let operands = try requireOperands(3, instruction: instruction)
            let comparison = try compare(
                read(operands[1], frame: frame),
                read(operands[2], frame: frame)
            )
            let answer = switch instruction.opcode {
            case .compareLess: comparison == .orderedAscending
            case .compareLessOrEqual: comparison != .orderedDescending
            case .compareGreater: comparison == .orderedDescending
            case .compareGreaterOrEqual: comparison != .orderedAscending
            default: false
            }
            try write(.boolean(answer), to: operands[0], frame: frame)
            return .next
        default:
            return nil
        }
    }

    private func integerBinary(
        _ instruction: PexInstruction,
        frame: PapyrusFrame,
        operation: (Int32, Int32) -> Int32
    ) throws(PapyrusFault) -> PapyrusFlow {
        let operands = try requireOperands(3, instruction: instruction)
        let result = try operation(
            integer(operands[1], frame: frame),
            integer(operands[2], frame: frame)
        )
        try write(.integer(result), to: operands[0], frame: frame)
        return .next
    }

    private func floatBinary(
        _ instruction: PexInstruction,
        frame: PapyrusFrame,
        operation: (Float, Float) -> Float
    ) throws(PapyrusFault) -> PapyrusFlow {
        let operands = try requireOperands(3, instruction: instruction)
        let result = try operation(
            float(operands[1], frame: frame),
            float(operands[2], frame: frame)
        )
        try write(.float(result), to: operands[0], frame: frame)
        return .next
    }

    private func integerDivision(
        _ instruction: PexInstruction,
        frame: PapyrusFrame,
        modulo: Bool
    ) throws(PapyrusFault) -> PapyrusFlow {
        let operands = try requireOperands(3, instruction: instruction)
        let left = try integer(operands[1], frame: frame)
        let right = try integer(operands[2], frame: frame)
        guard right != 0 else {
            throw .divideByZero(instruction: instructionIndex)
        }
        let wideLeft = Int64(left)
        let wideRight = Int64(right)
        let wideResult = modulo ? wideLeft % wideRight : wideLeft / wideRight
        try write(
            .integer(Int32(truncatingIfNeeded: wideResult)),
            to: operands[0],
            frame: frame
        )
        return .next
    }

    private func floatDivision(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow {
        let operands = try requireOperands(3, instruction: instruction)
        let left = try float(operands[1], frame: frame)
        let right = try float(operands[2], frame: frame)
        guard right != 0 else {
            throw .divideByZero(instruction: instructionIndex)
        }
        try write(.float(left / right), to: operands[0], frame: frame)
        return .next
    }

    private func integer(
        _ operand: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> Int32 {
        let value = try read(operand, frame: frame)
        guard case let .integer(integer) = value else {
            throw .typeMismatch(
                instruction: instructionIndex,
                expected: "Int",
                actual: value.typeName
            )
        }
        return integer
    }

    private func float(
        _ operand: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> Float {
        let value = try read(operand, frame: frame)
        guard case let .float(float) = value else {
            throw .typeMismatch(
                instruction: instructionIndex,
                expected: "Float",
                actual: value.typeName
            )
        }
        return float
    }

    func equal(_ left: PapyrusValue, _ right: PapyrusValue) -> Bool {
        switch (left, right) {
        case let (.integer(leftValue), .float(rightValue)):
            approximatelyEqual(Float(leftValue), rightValue)
        case let (.float(leftValue), .integer(rightValue)):
            approximatelyEqual(leftValue, Float(rightValue))
        case let (.float(leftValue), .float(rightValue)):
            approximatelyEqual(leftValue, rightValue)
        default:
            left == right
        }
    }

    private func compare(
        _ left: PapyrusValue,
        _ right: PapyrusValue
    ) throws(PapyrusFault) -> ComparisonResult {
        if case let .string(leftValue) = left, case let .string(rightValue) = right {
            return leftValue.caseInsensitiveCompare(rightValue)
        }
        let leftValue: Float
        let rightValue: Float
        do {
            leftValue = try runtime.coercion.toFloat(left)
            rightValue = try runtime.coercion.toFloat(right)
        } catch {
            throw .typeMismatch(
                instruction: instructionIndex,
                expected: "comparable values",
                actual: "\(left.typeName), \(right.typeName)"
            )
        }
        if approximatelyEqual(leftValue, rightValue) {
            return .orderedSame
        }
        return leftValue < rightValue ? .orderedAscending : .orderedDescending
    }

    private func approximatelyEqual(_ left: Float, _ right: Float) -> Bool {
        if left == right {
            return true
        }
        if left.isNaN || right.isNaN {
            return false
        }
        let scale = max(1, max(abs(left), abs(right)))
        return abs(left - right) <= Float.ulpOfOne * scale * 4
    }
}
