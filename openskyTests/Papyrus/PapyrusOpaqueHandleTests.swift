import Foundation
@testable import opensky
import Testing

struct PapyrusOpaqueHandleTests {
    typealias Support = PapyrusTestSupport

    @Test func opaqueWorldObjectHandlesRouteToNativeDispatch() throws {
        let dispatch = PapyrusRecordingNativeDispatch()
        let target = PexVariable(
            name: "target",
            typeName: "ObjectReference",
            userFlags: 0,
            initialValue: .null
        )
        let function = PexFixture.runtimeFunction(
            instructions: [
                op(
                    .callMethod,
                    .identifier("Activate"),
                    .identifier("target"),
                    .identifier("::nonevar"),
                    .integer(0)
                ),
                op(.returnValue, .null)
            ]
        )
        let script = PexFixture.runtimeObject(
            name: "OpaqueScript",
            variables: [target],
            states: [Support.state(functions: [("Run", function)])]
        )
        let runtime = PapyrusRuntime(
            files: [PexFixture.runtimeFile(objects: [script])],
            nativeDispatch: dispatch
        )
        let worldHandle = PapyrusObjectHandle(900)
        let instance = try runtime.makeInstance(
            scriptName: script.name,
            initialValues: ["target": .object(worldHandle)]
        )
        #expect(Support.value(runtime.invoke("Run", on: instance)) == PapyrusValue.none)
        #expect(dispatch.calls.first?.scriptName == "ObjectReference")
        #expect(dispatch.calls.first?.receiver == worldHandle)
    }

    private func op(_ opcode: PexOpcode, _ operands: PexValue...) -> PexInstruction {
        PexInstruction(opcode: opcode, operands: operands)
    }
}
