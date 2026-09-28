import Foundation
@testable import opensky
import Testing

struct PapyrusScalarOpcodeTests {
    typealias Support = PapyrusTestSupport

    private struct IntegerCase {
        let opcode: PexOpcode
        let left: Int32
        let right: Int32
        let expected: Int32
    }

    private struct FloatCase {
        let opcode: PexOpcode
        let left: Float
        let right: Float
        let expected: Float
    }

    private struct ComparisonCase {
        let opcode: PexOpcode
        let left: Int32
        let right: Int32
        let expected: Bool
    }

    @Test func noOpAssignmentCastAndReturn() {
        let outcome = run(
            returnType: "Float",
            locals: [typed("integer", "Int"), typed("result", "Float")],
            instructions: [
                op(.nop),
                op(.assign, .identifier("integer"), .integer(7)),
                op(.cast, .identifier("result"), .identifier("integer")),
                op(.returnValue, .identifier("result"))
            ]
        )
        #expect(Support.value(outcome) == .float(7))
    }

    @Test func integerArithmeticAndNegation() {
        let cases = [
            IntegerCase(opcode: .integerAdd, left: 9, right: 4, expected: 13),
            IntegerCase(opcode: .integerSubtract, left: 9, right: 4, expected: 5),
            IntegerCase(opcode: .integerMultiply, left: 9, right: 4, expected: 36),
            IntegerCase(opcode: .integerDivide, left: 9, right: 4, expected: 2),
            IntegerCase(opcode: .integerModulo, left: 9, right: 4, expected: 1)
        ]
        for entry in cases {
            let outcome = run(
                returnType: "Int",
                locals: [typed("result", "Int")],
                instructions: [
                    op(
                        entry.opcode,
                        .identifier("result"),
                        .integer(entry.left),
                        .integer(entry.right)
                    ),
                    op(.returnValue, .identifier("result"))
                ]
            )
            #expect(Support.value(outcome) == .integer(entry.expected))
        }
        let negated = run(
            returnType: "Int",
            locals: [typed("result", "Int")],
            instructions: [
                op(.integerNegate, .identifier("result"), .integer(12)),
                op(.returnValue, .identifier("result"))
            ]
        )
        #expect(Support.value(negated) == .integer(-12))
    }

    @Test func floatArithmeticAndNegation() {
        let cases = [
            FloatCase(opcode: .floatAdd, left: 9, right: 4, expected: 13),
            FloatCase(opcode: .floatSubtract, left: 9, right: 4, expected: 5),
            FloatCase(opcode: .floatMultiply, left: 9, right: 4, expected: 36),
            FloatCase(opcode: .floatDivide, left: 9, right: 4, expected: 2.25)
        ]
        for entry in cases {
            let outcome = run(
                returnType: "Float",
                locals: [typed("result", "Float")],
                instructions: [
                    op(
                        entry.opcode,
                        .identifier("result"),
                        .float(entry.left),
                        .float(entry.right)
                    ),
                    op(.returnValue, .identifier("result"))
                ]
            )
            #expect(Support.value(outcome) == .float(entry.expected))
        }
        let negated = run(
            returnType: "Float",
            locals: [typed("result", "Float")],
            instructions: [
                op(.floatNegate, .identifier("result"), .float(1.25)),
                op(.returnValue, .identifier("result"))
            ]
        )
        #expect(Support.value(negated) == .float(-1.25))
    }

    @Test func notAndAllComparisonOpcodes() {
        let notOutcome = run(
            returnType: "Bool",
            locals: [typed("result", "Bool")],
            instructions: [
                op(.not, .identifier("result"), .integer(0)),
                op(.returnValue, .identifier("result"))
            ]
        )
        #expect(Support.value(notOutcome) == .boolean(true))

        let cases = [
            ComparisonCase(opcode: .compareEqual, left: 4, right: 4, expected: true),
            ComparisonCase(opcode: .compareLess, left: 3, right: 4, expected: true),
            ComparisonCase(opcode: .compareLessOrEqual, left: 4, right: 4, expected: true),
            ComparisonCase(opcode: .compareGreater, left: 5, right: 4, expected: true),
            ComparisonCase(opcode: .compareGreaterOrEqual, left: 4, right: 4, expected: true)
        ]
        for entry in cases {
            let outcome = run(
                returnType: "Bool",
                locals: [typed("result", "Bool")],
                instructions: [
                    op(
                        entry.opcode,
                        .identifier("result"),
                        .integer(entry.left),
                        .integer(entry.right)
                    ),
                    op(.returnValue, .identifier("result"))
                ]
            )
            #expect(Support.value(outcome) == .boolean(entry.expected))
        }
    }

    @Test func relativeJumpAndConditionalJumps() {
        let unconditional = branchOutcome(
            op(.jump, .integer(1))
        )
        let whenTrue = branchOutcome(
            op(.jumpTrue, .boolean(true), .integer(1))
        )
        let whenFalse = branchOutcome(
            op(.jumpFalse, .boolean(false), .integer(1))
        )
        #expect(Support.value(unconditional) == .integer(2))
        #expect(Support.value(whenTrue) == .integer(2))
        #expect(Support.value(whenFalse) == .integer(2))
    }

    @Test func stringConcatenation() {
        let outcome = run(
            returnType: "String",
            locals: [typed("result", "String")],
            instructions: [
                op(
                    .stringConcatenate,
                    .identifier("result"),
                    .string("number "),
                    .integer(7)
                ),
                op(.returnValue, .identifier("result"))
            ]
        )
        #expect(Support.value(outcome) == .string("number 7"))
    }

    private func branchOutcome(_ branch: PexInstruction) -> PapyrusRunOutcome {
        run(
            returnType: "Int",
            locals: [typed("result", "Int")],
            instructions: [
                op(.assign, .identifier("result"), .integer(1)),
                branch,
                op(.returnValue, .identifier("result")),
                op(.assign, .identifier("result"), .integer(2)),
                op(.returnValue, .identifier("result"))
            ]
        )
    }

    private func run(
        returnType: String,
        locals: [PexTypedName],
        instructions: [PexInstruction]
    ) -> PapyrusRunOutcome {
        let run = function(
            returnType: returnType,
            locals: locals,
            instructions: instructions
        )
        let script = PexFixture.runtimeObject(
            name: "OpcodeScript",
            states: [Support.state(functions: [("Run", run)])]
        )
        let (runtime, handle) = Support.runtime(objects: [script])
        return runtime.invoke("Run", on: handle)
    }

    private func function(
        returnType: String,
        locals: [PexTypedName] = [],
        instructions: [PexInstruction]
    ) -> PexFunction {
        PexFixture.runtimeFunction(
            returnType: returnType,
            locals: locals,
            instructions: instructions
        )
    }

    private func typed(_ name: String, _ type: String) -> PexTypedName {
        PexTypedName(name: name, typeName: type)
    }

    private func op(_ opcode: PexOpcode, _ operands: PexValue...) -> PexInstruction {
        PexInstruction(opcode: opcode, operands: operands)
    }
}
