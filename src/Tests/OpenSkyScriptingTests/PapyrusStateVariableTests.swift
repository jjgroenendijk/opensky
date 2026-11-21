import Foundation
@testable import OpenSkyFormatsPEX
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

/// The hidden `::State` variable, which a script that overrides `GotoState` assigns.
@MainActor
struct PapyrusStateVariableTests {
    typealias Support = PapyrusTestSupport

    @Test func assigningTheStateVariableChangesTheActiveState() {
        let run = function(returnType: "Int", locals: [typed("result", "Int")], instructions: [
            op(.assign, .identifier("::State"), .string("Other")),
            op(
                .callMethod, .identifier("Pick"), .identifier("self"), .identifier("result"),
                .integer(0)
            ),
            op(.returnValue, .identifier("result"))
        ])
        let other = Support.state("Other", functions: [("Pick", returning(9))])
        let empty = Support.state(functions: [("Run", run), ("Pick", returning(1))])
        let (runtime, handle) = Support.runtime(
            objects: [PexFixture.runtimeObject(name: "StateScript", states: [empty, other])]
        )
        let picked = Support.value(runtime.invoke("Run", on: handle))
        #expect(runtime.instance(for: handle)?.activeState == "Other")
        #expect(picked == .integer(9))
    }

    @Test func readingTheStateVariableGivesTheActiveState() {
        let read = function(returnType: "String", instructions: [
            op(.assign, .identifier("::state"), .string("Busy")),
            op(.returnValue, .identifier("::State"))
        ])
        let script = PexFixture.runtimeObject(name: "StateScript", states: [
            Support.state(functions: [("Read", read)])
        ])
        let (runtime, handle) = Support.runtime(objects: [script])
        #expect(Support.value(runtime.invoke("Read", on: handle)) == .string("Busy"))
    }

    private func returning(_ value: Int32) -> PexFunction {
        function(returnType: "Int", instructions: [op(.returnValue, .integer(value))])
    }

    private func function(
        returnType: String, locals: [PexTypedName] = [], instructions: [PexInstruction]
    ) -> PexFunction {
        PexFixture.runtimeFunction(
            returnType: returnType, flags: [], parameters: [], locals: locals,
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
