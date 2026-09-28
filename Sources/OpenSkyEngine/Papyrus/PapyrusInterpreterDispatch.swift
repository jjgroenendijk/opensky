// Opcode fan-out kept separate from the execution loop.

import Foundation

nonisolated extension PapyrusInterpreter {
    func requireOperands(
        _ count: Int,
        instruction: PexInstruction
    ) throws(PapyrusFault) -> [PexValue] {
        guard instruction.operands.count >= count else {
            throw .invalidOperand(
                instruction: instructionIndex,
                detail: "\(instruction.opcode.name) needs \(count) operands"
            )
        }
        return instruction.operands
    }

    func step(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow {
        if let flow = try coreOp(instruction, frame: frame) {
            return flow
        }
        if let flow = try mathOp(instruction, frame: frame) {
            return flow
        }
        if let flow = try comparisonOp(instruction, frame: frame) {
            return flow
        }
        if let flow = try controlOp(instruction, frame: frame) {
            return flow
        }
        if let flow = try callOp(instruction, frame: frame) {
            return flow
        }
        if let flow = try memberOp(instruction, frame: frame) {
            return flow
        }
        if let flow = try arrayOp(instruction, frame: frame) {
            return flow
        }
        if case let .unknown(rawValue) = instruction.opcode {
            throw .unknownOpcode(instruction: instructionIndex, rawValue: rawValue)
        }
        throw .invalidOperand(
            instruction: instructionIndex,
            detail: "unhandled opcode \(instruction.opcode.name)"
        )
    }

    private func coreOp(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow? {
        switch instruction.opcode {
        case .nop:
            return .next
        case .assign:
            let operands = try requireOperands(2, instruction: instruction)
            try write(read(operands[1], frame: frame), to: operands[0], frame: frame)
            return .next
        case .cast:
            let operands = try requireOperands(2, instruction: instruction)
            let type = try destinationType(operands[0], frame: frame)
            let value = try cast(read(operands[1], frame: frame), to: type)
            try write(value, to: operands[0], frame: frame)
            return .next
        case .returnValue:
            let operands = try requireOperands(1, instruction: instruction)
            return try .returned(read(operands[0], frame: frame))
        default:
            return nil
        }
    }
}
