import FormatsTesting
import Foundation
@testable import OpenSkyFormatsPEX
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNoneAccessTests {
    typealias Support = PapyrusTestSupport

    @Test func aNoneArrayHasLengthZeroAndFindsNothing() {
        let result = run(
            locals: [
                PexTypedName(name: "values", typeName: "Int[]"),
                PexTypedName(name: "count", typeName: "Int"),
                PexTypedName(name: "found", typeName: "Int"),
                PexTypedName(name: "result", typeName: "Int")
            ],
            instructions: [
                op(.assign, .identifier("count"), .integer(9)),
                op(.arrayLength, .identifier("count"), .identifier("values")),
                op(
                    .arrayFindElement, .identifier("found"), .identifier("values"),
                    .integer(3), .integer(0)
                ),
                op(.integerAdd, .identifier("result"), .identifier("count"), .identifier("found")),
                op(.returnValue, .identifier("result"))
            ]
        )
        #expect(result?.value == .integer(-1))
        #expect(result?.noneTotal == 2)
    }

    @Test func anElementOfANoneArrayReadsAsTheDefault() {
        let result = run(
            locals: [
                PexTypedName(name: "values", typeName: "Int[]"),
                PexTypedName(name: "result", typeName: "Int")
            ],
            instructions: [
                op(.assign, .identifier("result"), .integer(7)),
                op(.arraySetElement, .identifier("values"), .integer(0), .integer(5)),
                op(.arrayGetElement, .identifier("result"), .identifier("values"), .integer(0)),
                op(.returnValue, .identifier("result"))
            ]
        )
        #expect(result?.value == .integer(0))
        #expect(result?.noneTotal == 2)
    }

    @Test func aPropertyOfANoneObjectReadsAsTheDefault() {
        let result = run(
            locals: [
                PexTypedName(name: "target", typeName: "ObjectReference"),
                PexTypedName(name: "result", typeName: "Int")
            ],
            instructions: [
                op(.assign, .identifier("result"), .integer(7)),
                op(.propertySet, .identifier("Count"), .identifier("target"), .integer(5)),
                op(
                    .propertyGet,
                    .identifier("Count"),
                    .identifier("target"),
                    .identifier("result")
                ),
                op(.returnValue, .identifier("result"))
            ]
        )
        #expect(result?.value == .integer(0))
        #expect(result?.noneTotal == 2)
    }

    private func run(
        locals: [PexTypedName],
        instructions: [PexInstruction]
    ) -> (value: PapyrusValue, noneTotal: Int)? {
        let function = PexFixture.runtimeFunction(locals: locals, instructions: instructions)
        let script = PexFixture.runtimeObject(
            name: "NoneScript",
            states: [Support.state(functions: [("Run", function)])]
        )
        let (runtime, handle) = Support.runtime(objects: [script])
        guard case let .completed(value) = runtime.invoke("Run", on: handle) else {
            Issue.record("the access on None stopped the function")
            return nil
        }
        return (value, runtime.tally.noneReceiverTotal)
    }

    private func op(_ opcode: PexOpcode, _ operands: PexValue...) -> PexInstruction {
        PexInstruction(opcode: opcode, operands: operands)
    }
}
