// One-dimensional Papyrus array opcodes.

import Foundation

nonisolated extension PapyrusInterpreter {
    func arrayOp(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow? {
        switch instruction.opcode {
        case .arrayCreate:
            try arrayCreate(instruction, frame: frame)
        case .arrayLength:
            try arrayLength(instruction, frame: frame)
        case .arrayGetElement:
            try arrayGet(instruction, frame: frame)
        case .arraySetElement:
            try arraySet(instruction, frame: frame)
        case .arrayFindElement:
            try arrayFind(instruction, frame: frame, reverse: false)
        case .arrayReverseFindElement:
            try arrayFind(instruction, frame: frame, reverse: true)
        default:
            nil
        }
    }

    private func arrayCreate(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow {
        let operands = try requireOperands(2, instruction: instruction)
        let type = try destinationType(operands[0], frame: frame)
        guard case let .array(elementType) = type else {
            throw .typeMismatch(
                instruction: instructionIndex,
                expected: "Array",
                actual: type.name
            )
        }
        let count = try arrayIndex(operands[1], frame: frame)
        guard count >= 0 else {
            throw .arrayBounds(instruction: instructionIndex, index: count, count: 0)
        }
        guard count <= runtime.limits.arrayLength else {
            throw .arrayLimitExceeded(instruction: instructionIndex, requested: count)
        }
        let array = PapyrusArray(
            elementType: elementType,
            elements: Array(repeating: elementType.defaultValue, count: count)
        )
        try write(.array(array), to: operands[0], frame: frame)
        return .next
    }

    private func arrayLength(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow {
        let operands = try requireOperands(2, instruction: instruction)
        let array = try array(operands[1], frame: frame)
        try write(.integer(Int32(array.elements.count)), to: operands[0], frame: frame)
        return .next
    }

    private func arrayGet(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow {
        let operands = try requireOperands(3, instruction: instruction)
        let array = try array(operands[1], frame: frame)
        let index = try arrayIndex(operands[2], frame: frame)
        guard array.elements.indices.contains(index) else {
            throw .arrayBounds(
                instruction: instructionIndex,
                index: index,
                count: array.elements.count
            )
        }
        try write(array.elements[index], to: operands[0], frame: frame)
        return .next
    }

    private func arraySet(
        _ instruction: PexInstruction,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusFlow {
        let operands = try requireOperands(3, instruction: instruction)
        let array = try array(operands[0], frame: frame)
        let index = try arrayIndex(operands[1], frame: frame)
        guard array.elements.indices.contains(index) else {
            throw .arrayBounds(
                instruction: instructionIndex,
                index: index,
                count: array.elements.count
            )
        }
        let value = try cast(
            read(operands[2], frame: frame),
            to: array.elementType
        )
        array.elements[index] = value
        return .next
    }

    private func arrayFind(
        _ instruction: PexInstruction,
        frame: PapyrusFrame,
        reverse: Bool
    ) throws(PapyrusFault) -> PapyrusFlow {
        let operands = try requireOperands(4, instruction: instruction)
        let array = try array(operands[1], frame: frame)
        let needle = try cast(
            read(operands[2], frame: frame),
            to: array.elementType
        )
        let requestedStart = try arrayIndex(operands[3], frame: frame)
        let found = reverse
            ? reverseIndex(of: needle, in: array, start: requestedStart)
            : forwardIndex(of: needle, in: array, start: requestedStart)
        try write(.integer(Int32(found)), to: operands[0], frame: frame)
        return .next
    }

    private func array(
        _ operand: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> PapyrusArray {
        let value = try read(operand, frame: frame)
        guard case let .array(array) = value else {
            throw .typeMismatch(
                instruction: instructionIndex,
                expected: "Array",
                actual: value.typeName
            )
        }
        return array
    }

    private func arrayIndex(
        _ operand: PexValue,
        frame: PapyrusFrame
    ) throws(PapyrusFault) -> Int {
        let value = try read(operand, frame: frame)
        guard case let .integer(index) = value else {
            throw .typeMismatch(
                instruction: instructionIndex,
                expected: "Int",
                actual: value.typeName
            )
        }
        return Int(index)
    }

    private func forwardIndex(
        of needle: PapyrusValue,
        in array: PapyrusArray,
        start: Int
    ) -> Int {
        let lowerBound = max(0, start)
        guard lowerBound < array.elements.count else {
            return -1
        }
        return array.elements[lowerBound...].firstIndex(where: { equal($0, needle) }) ?? -1
    }

    private func reverseIndex(
        of needle: PapyrusValue,
        in array: PapyrusArray,
        start: Int
    ) -> Int {
        guard !array.elements.isEmpty else {
            return -1
        }
        let upperBound = start < 0
            ? array.elements.count - 1
            : min(start, array.elements.count - 1)
        return array.elements[...upperBound].lastIndex(where: { equal($0, needle) }) ?? -1
    }
}
