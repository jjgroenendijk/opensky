// Defensive PEX container tests over synthetic bytecode only.

import Foundation
@testable import opensky
import Testing

@Suite("PEX container")
struct PexFileTests {
    @Test("decodes header, strings, debug info, flags, objects and functions")
    func decodesContainer() throws {
        let file = try PexFile(data: PexFixture.file())

        #expect(file.header.majorVersion == 3)
        #expect(file.header.minorVersion == 2)
        #expect(file.header.gameID == 1)
        #expect(file.header.compilationTime == 1_700_000_000)
        #expect(file.header.sourceFileName == "FixtureObject.psc")
        #expect(file.header.userName == "builder")
        #expect(file.header.machineName == "test-machine")
        #expect(file.strings.contains(""))
        #expect(file.strings.contains("M'aiq—雪"))

        let debug = try #require(file.debugInfo)
        #expect(debug.modificationTime == 1_700_000_001)
        #expect(debug.functions.count == 1)
        #expect(debug.functions[0].objectName == "FixtureObject")
        #expect(debug.functions[0].lineNumbers.count == 36)
        #expect(file.userFlags == [PexUserFlag(name: "UserFlag", bitIndex: 3)])

        let object = try #require(file.objects.first)
        #expect(object.name == "FixtureObject")
        #expect(object.parentClassName == "ParentObject")
        #expect(object.automaticStateName == "AutoState")
        #expect(object.variables.count == 6)
        #expect(object.variables.map(\.initialValue) == [
            .null,
            .identifier("literal"),
            .string("M'aiq—雪"),
            .integer(-42),
            .float(3.5),
            .boolean(true)
        ])
        let property = try #require(object.properties.first)
        #expect(property.flags == .automatic)
        #expect(property.automaticVariableName == "::property_var")
        #expect(property.readHandler == nil)
        #expect(property.writeHandler == nil)
        let handlerProperty = try #require(object.properties.last)
        #expect(handlerProperty.flags == [.readable, .writable])
        #expect(handlerProperty.automaticVariableName == nil)
        #expect(handlerProperty.readHandler?.flags == .global)
        #expect(handlerProperty.writeHandler?.flags == .native)

        let namedFunction = try #require(object.states.first?.functions.first)
        #expect(namedFunction.name == "function")
        #expect(namedFunction.function.parameters == [
            PexTypedName(name: "parameter", typeName: "Int")
        ])
        #expect(namedFunction.function.localVariables == [
            PexTypedName(name: "local", typeName: "Int")
        ])
    }

    @Test("decodes every Skyrim instruction encoding")
    func decodesEveryInstruction() throws {
        let file = try PexFile(data: PexFixture.file())
        let instructions = try #require(
            file.objects.first?.states.first?.functions.first?.function.instructions
        )

        #expect(instructions.count == 36)
        #expect(instructions.map(\.opcode.rawValue) == Array(UInt8(0x00) ... UInt8(0x23)))
        #expect(instructions[0x17].operands.count == 6)
        #expect(instructions[0x18].operands.count == 5)
        #expect(instructions[0x19].operands.count == 6)
        #expect(instructions[0x17].operands.suffix(2) == [.string("literal"), .boolean(true)])
    }

    @Test("preserves an unknown opcode for inventory")
    func preservesUnknownOpcode() throws {
        let file = try PexFile(data: PexFixture.file(
            instructions: [.init(opcode: 0xFE, operands: [])]
        ))
        let instruction = try #require(
            file.objects.first?.states.first?.functions.first?.function.instructions.first
        )
        #expect(instruction.opcode == .unknown(0xFE))
        #expect(instruction.operands.isEmpty)
    }

    @Test("rejects a string-table index that does not exist")
    func rejectsOutOfRangeStringIndex() {
        #expect(throws: PexError.stringIndexOutOfRange(
            index: .max,
            count: PexFixture.strings.count
        )) {
            try PexFile(data: PexFixture.file(objectNameIndex: .max))
        }
    }

    @Test("truncated streams throw PexError")
    func rejectsTruncation() {
        let full = PexFixture.file()
        for count in [0, 1, 15, full.count - 1] {
            #expect(throws: PexError.self) {
                try PexFile(data: Data(full.prefix(count)))
            }
        }
    }

    @Test("rejects wrong magic, game and newer format revisions")
    func rejectsUnsupportedHeaders() {
        #expect(throws: PexError.invalidMagic(0x1234_5678)) {
            try PexFile(data: PexFixture.file(magic: 0x1234_5678))
        }
        #expect(throws: PexError.unsupportedGameID(2)) {
            try PexFile(data: PexFixture.file(gameID: 2))
        }
        #expect(throws: PexError.unsupportedVersion(major: 3, minor: 3)) {
            try PexFile(data: PexFixture.file(minorVersion: 3))
        }
        #expect(throws: PexError.unsupportedVersion(major: 4, minor: 0)) {
            try PexFile(data: PexFixture.file(majorVersion: 4, minorVersion: 0))
        }
    }

    @Test("rejects a negative call vararg count")
    func rejectsNegativeVarargCount() {
        let call = PexFixture.Instruction(
            opcode: 0x17,
            operands: [
                .identifier(14),
                .identifier(15),
                .identifier(16),
                .integer(-1)
            ]
        )
        #expect(throws: PexError.invalidVarargCount(.integer(-1))) {
            try PexFile(data: PexFixture.file(instructions: [call]))
        }
    }
}
