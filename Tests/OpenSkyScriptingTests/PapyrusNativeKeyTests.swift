// Native call names are folded once, when the script is indexed. A call carries
// the folded key to the registry and keeps its own spelling for messages.

@testable import OpenSkyFormatsPEX
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeKeyTests {
    private typealias Support = PapyrusTestSupport

    @Test func compiledFunctionFoldsEachCallName() {
        let function = PexFixture.runtimeFunction(instructions: [
            Support.instruction(
                .callStatic, .identifier("Debug"), .identifier("TraceUser"),
                .identifier("::nonevar"), .integer(0)
            ),
            Support.instruction(.returnValue, .null),
            Support.instruction(
                .callMethod, .identifier("GetActorValue"), .identifier("self"),
                .identifier("::nonevar"), .integer(0)
            )
        ])
        let compiled = PapyrusCompiledFunction(function)
        #expect(compiled.callNameKeys(at: 0, spelling: "TraceUser")?.script == "debug")
        #expect(compiled.callNameKeys(at: 0, spelling: "TraceUser")?.function == "traceuser")
        #expect(compiled.callNameKeys(at: 1, spelling: "TraceUser") == nil)
        #expect(compiled.callNameKeys(at: 2, spelling: "GetActorValue")?
            .function == "getactorvalue")
        #expect(compiled.callNameKeys(at: 2, spelling: "Other") == nil)
    }

    @Test func staticAndParentNativeCallsCarryTheFoldedKey() {
        let dispatch = PapyrusRecordingNativeDispatch()
        let native = PexFixture.runtimeFunction(flags: .native, instructions: [])
        let base = PexFixture.runtimeObject(
            name: "BaseScript", states: [Support.state(functions: [("DoThing", native)])]
        )
        let run = PexFixture.runtimeFunction(instructions: [
            Support.instruction(
                .callStatic, .identifier("Debug"), .identifier("TraceUser"),
                .identifier("::nonevar"), .integer(0)
            ),
            Support.instruction(
                .callMethod, .identifier("DOTHING"), .identifier("self"),
                .identifier("::nonevar"), .integer(0)
            )
        ])
        let child = PexFixture.runtimeObject(
            name: "ChildScript", parent: "BaseScript",
            states: [Support.state(functions: [("Run", run)])]
        )
        let (runtime, handle) = Support.runtime(objects: [child, base], nativeDispatch: dispatch)
        _ = runtime.invoke("Run", on: handle)
        #expect(dispatch.calls.map(\.key) == [
            PapyrusNativeKey(scriptName: "Debug", functionName: "TraceUser"),
            PapyrusNativeKey(scriptName: "BaseScript", functionName: "DoThing")
        ])
        #expect(dispatch.calls.map(\.qualifiedName) == ["Debug.TraceUser", "BaseScript.DOTHING"])
    }
}
