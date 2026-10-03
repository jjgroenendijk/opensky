import FormatsPEXTesting
@testable import OpenSkyFormatsPEX
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusInheritanceTests {
    private typealias Support = PapyrusTestSupport

    @Test func gotoStateEndsTheOldStateThenBeginsTheNewOne() {
        let dispatch = PapyrusRecordingNativeDispatch()
        let run = function([
            op(
                .callMethod,
                .identifier("GotoState"),
                .identifier("self"),
                .identifier("::nonevar"),
                .integer(1),
                .string("Armed")
            ),
            op(
                .callStatic,
                .identifier("Debug"),
                .identifier("AfterGoto"),
                .identifier("::nonevar"),
                .integer(0)
            ),
            op(.returnValue, .null)
        ])
        let script = PexFixture.runtimeObject(
            name: "HookScript",
            parent: "",
            automaticState: "Idle",
            variables: [],
            states: [
                Support.state(functions: [("Run", run)]),
                Support.state("Idle", functions: [("OnEndState", mark("EndIdle"))]),
                Support.state("Armed", functions: [("OnBeginState", mark("BeginArmed"))])
            ]
        )
        let (runtime, handle) = Support.runtime(objects: [script], nativeDispatch: dispatch)
        _ = runtime.invoke("Run", on: handle)
        #expect(dispatch.calls.map(\.functionName) == ["EndIdle", "BeginArmed", "AfterGoto"])
        #expect(runtime.instance(for: handle)?.activeState == "Armed")
    }

    @Test func aChildFunctionReadsAndWritesItsParentsVariable() throws {
        let variable = PexVariable(
            name: "::Type_var",
            typeName: "Int",
            userFlags: 0,
            initialValue: .integer(1)
        )
        let parent = PexFixture.runtimeObject(
            name: "Base", parent: "", automaticState: "", variables: [variable],
            states: [Support.state(functions: [])]
        )
        let bump = PexFixture.runtimeFunction(returnType: "Int", locals: [], instructions: [
            op(.assign, .identifier("::Type_var"), .integer(3)),
            op(.returnValue, .identifier("::Type_var"))
        ])
        let child = PexFixture.runtimeObject(
            name: "Plate", parent: "Base", automaticState: "", variables: [],
            states: [Support.state(functions: [("Bump", bump)])]
        )
        let runtime = PapyrusRuntime(files: [PexFixture.runtimeFile(objects: [child, parent])])
        let handle = try runtime.makeInstance(scriptName: "Plate")
        #expect(Support.value(runtime.invoke("Bump", on: handle)) == .integer(3))
        #expect(runtime.instances[handle]?
            .value(named: "::Type_var", declaredBy: "Base") == .integer(3))
    }

    private func mark(_ name: String) -> PexFunction {
        function([
            op(
                .callStatic,
                .identifier("Debug"),
                .identifier(name),
                .identifier("::nonevar"),
                .integer(0)
            ),
            op(.returnValue, .null)
        ])
    }

    private func function(_ instructions: [PexInstruction]) -> PexFunction {
        PexFixture.runtimeFunction(returnType: "None", locals: [], instructions: instructions)
    }

    private func op(_ opcode: PexOpcode, _ operands: PexValue...) -> PexInstruction {
        PexInstruction(opcode: opcode, operands: operands)
    }
}
