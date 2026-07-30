// Papyrus opcode and external-call census tests.

import Foundation
@testable import opensky
import Testing

@Suite("PEX inventory")
struct PexInventoryTests {
    @Test("ranks opcodes and external call targets")
    func ranksSurface() throws {
        let instructions = PexFixture.everyInstruction + [
            .init(opcode: 0x17, operands: [
                .identifier(14),
                .identifier(15),
                .identifier(16),
                .integer(0)
            ])
        ]
        let file = try PexFile(data: PexFixture.file(instructions: instructions))
        var inventory = PexInventory()
        inventory.record(file)

        #expect(inventory.scriptTotal == 1)
        #expect(inventory.functionTotal == 3)
        #expect(inventory.instructionTotal == 37)
        #expect(inventory.rankedOpcodes.first?.name == "callmethod")
        #expect(inventory.rankedOpcodes.first?.count == 2)
        #expect(inventory.externalCallTotal == 4)
        let hottestCall = try #require(inventory.rankedExternalCalls.first)
        #expect(hottestCall.name == "_self.method")
        #expect(hottestCall.count == 2)
        #expect(inventory.rankedExternalCalls.contains {
            $0.name == "ParentObject.parentCall" && $0.count == 1
        })
        #expect(inventory.rankedExternalCalls.contains {
            $0.name == "StaticClass.staticCall" && $0.count == 1
        })
        #expect(inventory.unknownOpcodeTotal == 0)
    }

    @Test("caps names but preserves totals")
    func boundedNames() throws {
        let file = try PexFile(data: PexFixture.file())
        var inventory = PexInventory(nameLimit: 1)
        inventory.record(file)
        inventory.noteDecodeFailure(path: "scripts\\one.pex")
        inventory.noteDecodeFailure(path: "scripts\\two.pex")

        #expect(inventory.externalCallTotal == 3)
        #expect(inventory.rankedExternalCalls.count == 1)
        #expect(inventory.unnamedExternalCalls == 2)
        #expect(inventory.decodeFailureTotal == 2)
        #expect(inventory.rankedDecodeFailures.count == 1)
        #expect(inventory.unnamedDecodeFailures == 1)
    }

    @Test("counts preserved unknown opcodes")
    func countsUnknownOpcodes() throws {
        let file = try PexFile(data: PexFixture.file(
            instructions: [
                .init(opcode: 0xFE, operands: []),
                .init(opcode: 0xFE, operands: [])
            ]
        ))
        var inventory = PexInventory()
        inventory.record(file)
        #expect(inventory.unknownOpcodeTotal == 2)
        let opcode = try #require(inventory.rankedOpcodes.first)
        #expect(inventory.rankedOpcodes.count == 1)
        #expect(opcode.name == "unknown(0xFE)")
        #expect(opcode.count == 2)
    }
}
