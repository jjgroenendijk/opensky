// Relative branch opcodes.

import Foundation

nonisolated extension PapyrusInterpreter {
    func controlOp(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow? {
        switch instruction.opcode {
        case .jump:
            let operands = try requireOperands(1, instruction: instruction)
            return try .jump(jumpTarget(operands[0], frame: frame))
        case .jumpTrue, .jumpFalse:
            let operands = try requireOperands(2, instruction: instruction)
            let condition = try runtime.coercion.toBoolean(read(operands[0], frame: frame))
            let shouldJump = instruction.opcode == .jumpTrue ? condition : !condition
            return try shouldJump
                ? .jump(jumpTarget(operands[1], frame: frame))
                : .next
        default:
            return nil
        }
    }

    private func jumpTarget(
        _ operand: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> Int {
        guard case let .integer(offset) = operand else {
            throw .typeMismatch(
                instruction: instructionIndex,
                expected: "Int jump offset",
                actual: runtime.runtimeValue(operand).typeName
            )
        }
        let target = frame.instructionIndex + Int(offset)
        guard (0 ... frame.function.instructions.count).contains(target) else {
            throw .invalidJump(instruction: instructionIndex, target: target)
        }
        return target
    }
}
