// Synthetic Skyrim PEX 3.2 builder. Every byte is assembled in code from the
// public UESP layout; no compiled game script is committed.

import Foundation
@testable import opensky

enum PexFixture {
    enum Value {
        case null
        case identifier(UInt16)
        case string(UInt16)
        case integer(Int32)
        case float(Float)
        case boolean(Bool)
    }

    struct Instruction {
        let opcode: UInt8
        let operands: [Value]
    }

    static let strings = [
        "",
        "FixtureObject",
        "ParentObject",
        "Fixture documentation",
        "AutoState",
        "variable",
        "Int",
        "property",
        "::property_var",
        "state",
        "function",
        "None",
        "parameter",
        "local",
        "method",
        "_self",
        "result",
        "StaticClass",
        "literal",
        "UserFlag",
        "M'aiq—雪",
        "parentCall",
        "staticCall"
    ]

    static var everyInstruction: [Instruction] {
        (UInt8(0x00) ... UInt8(0x23)).map { raw in
            let opcode = PexOpcode(rawValue: raw)
            var operands = Array(
                repeating: Value.identifier(13),
                count: opcode.fixedOperandCount
            )
            switch opcode {
            case .callMethod:
                operands = [.identifier(14), .identifier(15), .identifier(16)]
            case .callParent:
                operands = [.identifier(21), .identifier(16)]
            case .callStatic:
                operands = [.identifier(17), .identifier(22), .identifier(16)]
            default:
                break
            }
            if opcode.hasVarargs {
                operands += [.integer(2), .string(18), .boolean(true)]
            }
            return Instruction(opcode: raw, operands: operands)
        }
    }

    static func file(
        instructions: [Instruction] = everyInstruction,
        objectNameIndex: UInt16 = 1,
        magic: UInt32 = PexFile.magic,
        majorVersion: UInt8 = 3,
        minorVersion: UInt8 = 2,
        gameID: UInt16 = 1
    ) -> Data {
        var out = Data()
        out.appendBigEndian(magic)
        out.append(majorVersion)
        out.append(minorVersion)
        out.appendBigEndian(gameID)
        out.appendBigEndian(UInt64(1_700_000_000))
        out.appendPexString("FixtureObject.psc")
        out.appendPexString("builder")
        out.appendPexString("test-machine")
        out.appendBigEndian(UInt16(strings.count))
        for string in strings {
            out.appendPexString(string)
        }

        out.append(1) // has debug info
        out.appendBigEndian(UInt64(1_700_000_001))
        out.appendBigEndian(UInt16(1))
        out.appendBigEndian(UInt16(1)) // object name
        out.appendBigEndian(UInt16(9)) // state name
        out.appendBigEndian(UInt16(10)) // function name
        out.append(0) // normal function
        out.appendBigEndian(UInt16(instructions.count))
        for line in 0 ..< instructions.count {
            out.appendBigEndian(UInt16(line + 1))
        }

        out.appendBigEndian(UInt16(1)) // user flag count
        out.appendBigEndian(UInt16(19))
        out.append(3)
        out.appendBigEndian(UInt16(1)) // object count
        out.appendBigEndian(objectNameIndex)
        let object = objectData(instructions: instructions)
        out.appendBigEndian(UInt32(object.count + 4))
        out.append(object)
        return out
    }

    static func instruction(opcode: UInt8, operands: [Value] = []) -> Data {
        var out = Data([opcode])
        for operand in operands {
            out.append(value: operand)
        }
        return out
    }

    private static func objectData(instructions: [Instruction]) -> Data {
        var out = Data()
        out.appendBigEndian(UInt16(2)) // parent
        out.appendBigEndian(UInt16(3)) // documentation
        out.appendBigEndian(UInt32(1 << 3))
        out.appendBigEndian(UInt16(4)) // automatic state

        let values: [Value] = [
            .null,
            .identifier(18),
            .string(20),
            .integer(-42),
            .float(3.5),
            .boolean(true)
        ]
        out.appendBigEndian(UInt16(values.count))
        for (index, value) in values.enumerated() {
            out.appendBigEndian(UInt16(5))
            out.appendBigEndian(UInt16(6))
            out.appendBigEndian(UInt32(index))
            out.append(value: value)
        }

        out.appendBigEndian(UInt16(2)) // property count
        out.appendBigEndian(UInt16(7))
        out.appendBigEndian(UInt16(6))
        out.appendBigEndian(UInt16(3))
        out.appendBigEndian(UInt32(0))
        out.append(PexPropertyFlags.automatic.rawValue)
        out.appendBigEndian(UInt16(8))

        out.appendBigEndian(UInt16(7))
        out.appendBigEndian(UInt16(6))
        out.appendBigEndian(UInt16(3))
        out.appendBigEndian(UInt32(0))
        out.append(
            PexPropertyFlags.readable.rawValue
                | PexPropertyFlags.writable.rawValue
        )
        out.append(functionData(
            instructions: [],
            flags: PexFunctionFlags.global.rawValue
        ))
        out.append(functionData(
            instructions: [],
            flags: PexFunctionFlags.native.rawValue
        ))

        out.appendBigEndian(UInt16(1)) // state count
        out.appendBigEndian(UInt16(9))
        out.appendBigEndian(UInt16(1)) // function count
        out.appendBigEndian(UInt16(10))
        out.append(functionData(instructions: instructions))
        return out
    }

    private static func functionData(
        instructions: [Instruction],
        flags: UInt8 = 0
    ) -> Data {
        var out = Data()
        out.appendBigEndian(UInt16(11)) // return type
        out.appendBigEndian(UInt16(3)) // documentation
        out.appendBigEndian(UInt32(0))
        out.append(flags)
        out.appendBigEndian(UInt16(1)) // parameter count
        out.appendBigEndian(UInt16(12))
        out.appendBigEndian(UInt16(6))
        out.appendBigEndian(UInt16(1)) // local count
        out.appendBigEndian(UInt16(13))
        out.appendBigEndian(UInt16(6))
        out.appendBigEndian(UInt16(instructions.count))
        for instruction in instructions {
            out.append(instruction: instruction)
        }
        return out
    }
}

extension Data {
    fileprivate mutating func appendBigEndian(_ value: some FixedWidthInteger) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    fileprivate mutating func appendPexString(_ string: String) {
        let bytes = Data(string.utf8)
        appendBigEndian(UInt16(bytes.count))
        append(bytes)
    }

    fileprivate mutating func append(value: PexFixture.Value) {
        switch value {
        case .null:
            append(0)
        case let .identifier(index):
            append(1)
            appendBigEndian(index)
        case let .string(index):
            append(2)
            appendBigEndian(index)
        case let .integer(value):
            append(3)
            appendBigEndian(UInt32(bitPattern: value))
        case let .float(value):
            append(4)
            appendBigEndian(value.bitPattern)
        case let .boolean(value):
            append(5)
            append(value ? 1 : 0)
        }
    }

    fileprivate mutating func append(instruction: PexFixture.Instruction) {
        append(instruction.opcode)
        for operand in instruction.operands {
            append(value: operand)
        }
    }
}
