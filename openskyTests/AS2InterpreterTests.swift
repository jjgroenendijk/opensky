// Opcode behavior of the AS2 interpreter (milestone 8.3.2): arithmetic,
// comparison, bitwise, stack, constant pool, registers, and branches. Every
// stream is assembled from synthetic bytes by `SWFActionFixture`.

import Foundation
@testable import opensky
import Testing

struct AS2InterpreterTests {
    @Test func addsNumbers() {
        let value = AS2Fixture.evaluate([
            AS2Fixture.push([.integer(2), .integer(3)]), AS2Fixture.opcode(0x47)
        ])
        #expect(AS2Fixture.number(value) == 5)
    }

    @Test func addConcatenatesWhenEitherOperandIsAString() {
        let left = AS2Fixture.evaluate([
            AS2Fixture.push([.string("a"), .integer(1)]), AS2Fixture.opcode(0x47)
        ])
        #expect(AS2Fixture.string(left) == "a1")
        let right = AS2Fixture.evaluate([
            AS2Fixture.push([.integer(1), .string("a")]), AS2Fixture.opcode(0x47)
        ])
        #expect(AS2Fixture.string(right) == "1a")
    }

    @Test func subtractDivideAndModuloKeepOperandOrder() {
        #expect(AS2Fixture.number(binary(10, 3, 0x0B)) == 7)
        #expect(AS2Fixture.number(binary(10, 4, 0x0D)) == 2.5)
        #expect(AS2Fixture.number(binary(5, 2, 0x3F)) == 1)
        #expect(AS2Fixture.number(binary(-5, 2, 0x3F)) == -1)
        #expect(AS2Fixture.number(binary(6, 7, 0x0C)) == 42)
        #expect(AS2Fixture.number(binary(1, 0, 0x0D)) == .infinity)
    }

    @Test func incrementDecrementAndConversionOpcodes() {
        #expect(AS2Fixture.number(unary(.integer(4), 0x50)) == 5)
        #expect(AS2Fixture.number(unary(.integer(4), 0x51)) == 3)
        #expect(AS2Fixture.number(unary(.string("12"), 0x4A)) == 12)
        #expect(AS2Fixture.string(unary(.integer(12), 0x4B)) == "12")
        #expect(AS2Fixture.boolean(unary(.string(""), 0x12)) == true)
        #expect(AS2Fixture.boolean(unary(.integer(1), 0x12)) == false)
    }

    @Test func comparisonOpcodesPushBooleans() {
        #expect(AS2Fixture.boolean(binary(1, 2, 0x48)) == true)
        #expect(AS2Fixture.boolean(binary(2, 1, 0x48)) == false)
        #expect(AS2Fixture.boolean(binary(2, 1, 0x67)) == true)
        #expect(AS2Fixture.boolean(binary(1, 1, 0x49)) == true)
        #expect(AS2Fixture.boolean(binary(1, 1, 0x66)) == true)
        let mixed = AS2Fixture.evaluate([
            AS2Fixture.push([.string("1"), .integer(1)]), AS2Fixture.opcode(0x66)
        ])
        #expect(AS2Fixture.boolean(mixed) == false)
    }

    @Test func bitwiseOpcodesUseThirtyTwoBitIntegers() {
        #expect(AS2Fixture.number(binary(12, 10, 0x60)) == 8)
        #expect(AS2Fixture.number(binary(12, 10, 0x61)) == 14)
        #expect(AS2Fixture.number(binary(12, 10, 0x62)) == 6)
        #expect(AS2Fixture.number(binary(1, 4, 0x63)) == 16)
        #expect(AS2Fixture.number(binary(-16, 2, 0x64)) == -4)
        #expect(AS2Fixture.number(binary(-1, 28, 0x65)) == 15)
    }

    @Test func shiftCountsUseOnlyTheLowFiveBits() {
        #expect(AS2Fixture.number(binary(1, 33, 0x63)) == 2)
    }

    @Test func stackOpcodesDuplicateAndSwap() {
        let duplicated = AS2Fixture.evaluate([
            AS2Fixture.push([.integer(7)]),
            AS2Fixture.opcode(0x4C),
            AS2Fixture.opcode(0x47)
        ])
        #expect(AS2Fixture.number(duplicated) == 14)
        let swapped = AS2Fixture.evaluate([
            AS2Fixture.push([.string("a"), .string("b")]),
            AS2Fixture.opcode(0x4D),
            AS2Fixture.opcode(0x47)
        ])
        #expect(AS2Fixture.string(swapped) == "ba")
    }

    @Test func registersRoundTripThroughStoreRegister() {
        let value = AS2Fixture.evaluate([
            AS2Fixture.push([.integer(9)]),
            SWFActionFixture.storeRegister(2),
            AS2Fixture.opcode(0x17),
            AS2Fixture.push([.register(2)])
        ])
        #expect(AS2Fixture.number(value) == 9)
    }

    @Test func constantPoolResolvesBothReferenceWidths() {
        let pool = (0 ..< 300).map { "name\($0)" }
        let narrow = AS2Fixture.evaluate([
            SWFActionFixture.constantPool(pool), AS2Fixture.push([.constant8(3)])
        ])
        #expect(AS2Fixture.string(narrow) == "name3")
        let wide = AS2Fixture.evaluate([
            SWFActionFixture.constantPool(pool), AS2Fixture.push([.constant16(299)])
        ])
        #expect(AS2Fixture.string(wide) == "name299")
        let stale = AS2Fixture.evaluate([
            SWFActionFixture.constantPool(pool), AS2Fixture.push([.constant16(400)])
        ])
        #expect(stale == .undefined)
    }

    @Test func forwardJumpSkipsRecords() {
        let skipped = [AS2Fixture.push([.integer(2)])]
        let value = AS2Fixture.evaluate(
            [AS2Fixture.push([.integer(1)]), AS2Fixture.jump(over: skipped)] + skipped
        )
        #expect(AS2Fixture.number(value) == 1)
    }

    @Test func backwardBranchRunsALoopToCompletion() {
        let body: [AS2Fixture.Action] = [
            AS2Fixture.push([.string("i"), .string("i")]),
            AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.integer(1)]),
            AS2Fixture.opcode(0x47),
            AS2Fixture.opcode(0x1D),
            AS2Fixture.push([.string("i")]),
            AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.integer(3)]),
            AS2Fixture.opcode(0x48)
        ]
        let actions = AS2Fixture.setVariable("i", .integer(0))
            + body
            + [AS2Fixture.loopBack(over: body)]
            + AS2Fixture.getVariable("i")
        #expect(AS2Fixture.number(AS2Fixture.evaluate(actions)) == 3)
    }

    @Test func branchIntoTheMiddleOfARecordFaults() {
        let result = AS2Fixture.run([
            SWFActionFixture.branch(code: 0x99, offset: 1),
            AS2Fixture.push([.integer(1)])
        ])
        #expect(result.fault?.kind == "invalidJump")
        #expect(result.completed == false)
    }

    @Test func branchToTheEndOfTheBlockIsLegal() {
        let tail = [AS2Fixture.push([.integer(2)]), AS2Fixture.returnAction]
        let result = AS2Fixture.run(
            [AS2Fixture.push([.integer(1)]), AS2Fixture.jump(over: tail)] + tail
        )
        #expect(result.completed)
        #expect(result.value == .undefined)
    }

    // MARK: - Helpers

    private func binary(_ left: Int32, _ right: Int32, _ code: UInt8) -> AS2Value {
        AS2Fixture.evaluate([
            AS2Fixture.push([.integer(left), .integer(right)]), AS2Fixture.opcode(code)
        ])
    }

    private func unary(_ value: SWFActionFixture.PushValue, _ code: UInt8) -> AS2Value {
        AS2Fixture.evaluate([AS2Fixture.push([value]), AS2Fixture.opcode(code)])
    }
}
