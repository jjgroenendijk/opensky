// Function, instruction and typed-value sections of the PEX decoder.

import Foundation

nonisolated extension PexDecoder {
    mutating func decodeFunction(from objectReader: inout PexReader) throws -> PexFunction {
        let returnType = try resolve(objectReader.readUInt16())
        let documentation = try resolve(objectReader.readUInt16())
        let userFlags = try objectReader.readUInt32()
        let flags = try PexFunctionFlags(rawValue: objectReader.readUInt8())
        let parameters = try decodeTypedNames(from: &objectReader)
        let locals = try decodeTypedNames(from: &objectReader)
        let instructionCount = try Int(objectReader.readUInt16())
        var instructions: [PexInstruction] = []
        instructions.reserveCapacity(instructionCount)
        for _ in 0 ..< instructionCount {
            try instructions.append(decodeInstruction(from: &objectReader))
        }
        return PexFunction(
            returnTypeName: returnType,
            documentation: documentation,
            userFlags: userFlags,
            flags: flags,
            parameters: parameters,
            localVariables: locals,
            instructions: instructions
        )
    }

    private mutating func decodeTypedNames(
        from objectReader: inout PexReader
    ) throws -> [PexTypedName] {
        let count = try Int(objectReader.readUInt16())
        var result: [PexTypedName] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            try result.append(PexTypedName(
                name: resolve(objectReader.readUInt16()),
                typeName: resolve(objectReader.readUInt16())
            ))
        }
        return result
    }

    private mutating func decodeInstruction(
        from objectReader: inout PexReader
    ) throws -> PexInstruction {
        let opcode = try PexOpcode(rawValue: objectReader.readUInt8())
        var operands: [PexValue] = []
        operands.reserveCapacity(opcode.fixedOperandCount + (opcode.hasVarargs ? 1 : 0))
        for _ in 0 ..< opcode.fixedOperandCount {
            try operands.append(decodeValue(from: &objectReader))
        }
        if opcode.hasVarargs {
            let countValue = try decodeValue(from: &objectReader)
            operands.append(countValue)
            guard case let .integer(rawCount) = countValue, rawCount >= 0 else {
                throw PexError.invalidVarargCount(countValue)
            }
            for _ in 0 ..< Int(rawCount) {
                try operands.append(decodeValue(from: &objectReader))
            }
        }
        return PexInstruction(opcode: opcode, operands: operands)
    }

    mutating func decodeValue(from objectReader: inout PexReader) throws -> PexValue {
        let type = try objectReader.readUInt8()
        switch type {
        case 0:
            return .null
        case 1:
            return try .identifier(resolve(objectReader.readUInt16()))
        case 2:
            return try .string(resolve(objectReader.readUInt16()))
        case 3:
            return try .integer(objectReader.readInt32())
        case 4:
            return try .float(objectReader.readFloat32())
        case 5:
            return try .boolean(objectReader.readUInt8() != 0)
        default:
            throw PexError.invalidValueType(type)
        }
    }
}
