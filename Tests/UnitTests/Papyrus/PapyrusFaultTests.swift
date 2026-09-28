import Foundation
@testable import opensky
import Testing

struct PapyrusFaultTests {
    typealias Support = PapyrusTestSupport

    @Test func instructionBudgetStopsARunawayLoop() {
        var limits = PapyrusLimits.standard
        limits.instructionBudget = 25
        let (runtime, handle) = runtime(
            instructions: [op(.jump, .integer(-1))],
            limits: limits
        )
        let outcome = runtime.invoke("Run", on: handle)
        #expect(Support.fault(outcome)?.kind == "budgetExhausted")
        #expect(runtime.tally.instructionsExecuted == 25)
    }

    @Test func explicitFramesStopAtTheCallDepthCap() {
        var limits = PapyrusLimits.standard
        limits.callDepth = 3
        let call = op(
            .callMethod,
            .identifier("Run"),
            .identifier("self"),
            .identifier("::nonevar"),
            .integer(0)
        )
        let (runtime, handle) = runtime(instructions: [call], limits: limits)
        #expect(Support.fault(runtime.invoke("Run", on: handle))?.kind == "callDepthExceeded")
    }

    @Test func invalidJumpIsAFault() {
        let (runtime, handle) = runtime(
            instructions: [op(.jump, .integer(100))]
        )
        #expect(Support.fault(runtime.invoke("Run", on: handle))?.kind == "invalidJump")
    }

    @Test func typeMismatchIsAFault() {
        let (runtime, handle) = runtime(
            locals: [PexTypedName(name: "result", typeName: "Int")],
            instructions: [
                op(
                    .integerAdd,
                    .identifier("result"),
                    .string("wrong"),
                    .integer(1)
                )
            ]
        )
        #expect(Support.fault(runtime.invoke("Run", on: handle))?.kind == "typeMismatch")
    }

    @Test func unknownOpcodeIsAFault() {
        let (runtime, handle) = runtime(
            instructions: [op(.unknown(0xFF))]
        )
        #expect(Support.fault(runtime.invoke("Run", on: handle)) == .unknownOpcode(
            instruction: 0,
            rawValue: 0xFF
        ))
    }

    @Test func divideByZeroAndBadArrayIndexAreFaults() {
        let (divideRuntime, divideHandle) = runtime(
            locals: [PexTypedName(name: "result", typeName: "Int")],
            instructions: [
                op(
                    .integerDivide,
                    .identifier("result"),
                    .integer(1),
                    .integer(0)
                )
            ]
        )
        #expect(
            Support.fault(divideRuntime.invoke("Run", on: divideHandle))?.kind
                == "divideByZero"
        )

        let (arrayRuntime, arrayHandle) = runtime(
            locals: [
                PexTypedName(name: "values", typeName: "Int[]"),
                PexTypedName(name: "result", typeName: "Int")
            ],
            instructions: [
                op(.arrayCreate, .identifier("values"), .integer(1)),
                op(
                    .arrayGetElement,
                    .identifier("result"),
                    .identifier("values"),
                    .integer(4)
                )
            ]
        )
        #expect(
            Support.fault(arrayRuntime.invoke("Run", on: arrayHandle))?.kind
                == "arrayBounds"
        )
    }

    private func runtime(
        locals: [PexTypedName] = [],
        instructions: [PexInstruction],
        limits: PapyrusLimits = .standard
    ) -> (PapyrusRuntime, PapyrusObjectHandle) {
        let function = PexFixture.runtimeFunction(
            locals: locals,
            instructions: instructions
        )
        let script = PexFixture.runtimeObject(
            name: "FaultScript",
            states: [Support.state(functions: [("Run", function)])]
        )
        return Support.runtime(objects: [script], limits: limits)
    }

    private func op(_ opcode: PexOpcode, _ operands: PexValue...) -> PexInstruction {
        PexInstruction(opcode: opcode, operands: operands)
    }
}
