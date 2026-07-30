import Foundation
@testable import opensky
import Testing

struct PapyrusRuntimeTests {
    typealias Support = PapyrusTestSupport

    @Test func initialValuesOverrideCompilerBackingVariables() throws {
        let variable = PexVariable(
            name: "::property_var",
            typeName: "Int",
            userFlags: 0,
            initialValue: .integer(2)
        )
        let read = function(
            returnType: "Int",
            instructions: [op(.returnValue, .identifier("::property_var"))]
        )
        let script = object(
            "InitialScript",
            variables: [variable],
            states: [Support.state(functions: [("Read", read)])]
        )
        let runtime = PapyrusRuntime(files: [PexFixture.runtimeFile(objects: [script])])
        let handle = try runtime.makeInstance(
            scriptName: script.name,
            initialValues: ["::property_var": .integer(42)]
        )
        #expect(Support.value(runtime.invoke("Read", on: handle)) == .integer(42))
    }

    @Test func stateResolutionFollowsDerivedAndParentPriority() throws {
        let parent = object(
            "Parent",
            automaticState: "Active",
            states: [
                Support.state("Active", functions: [("Pick", returning(2))]),
                Support.state(functions: [("Pick", returning(4))])
            ]
        )
        let child = object(
            "Child",
            parent: "Parent",
            automaticState: "Active",
            states: [
                Support.state("Active", functions: [("Pick", returning(1))]),
                Support.state(functions: [("Pick", returning(3))])
            ]
        )
        let runtime = PapyrusRuntime(files: [PexFixture.runtimeFile(objects: [child, parent])])
        let handle = try runtime.makeInstance(scriptName: "Child")
        #expect(Support.value(runtime.invoke("Pick", on: handle)) == .integer(1))

        let childWithoutActive = object(
            "ChildWithoutActive",
            parent: "Parent",
            automaticState: "Active",
            states: [Support.state(functions: [("Pick", returning(3))])]
        )
        let secondRuntime = PapyrusRuntime(
            files: [PexFixture.runtimeFile(objects: [childWithoutActive, parent])]
        )
        let secondHandle = try secondRuntime.makeInstance(scriptName: "ChildWithoutActive")
        #expect(Support.value(secondRuntime.invoke("Pick", on: secondHandle)) == .integer(2))

        let parentWithoutActive = object(
            "ParentWithoutActive",
            states: [Support.state(functions: [("Pick", returning(4))])]
        )
        let childDefault = object(
            "ChildDefault",
            parent: "ParentWithoutActive",
            automaticState: "Active",
            states: [Support.state(functions: [("Pick", returning(3))])]
        )
        let thirdRuntime = PapyrusRuntime(
            files: [PexFixture.runtimeFile(objects: [childDefault, parentWithoutActive])]
        )
        let thirdHandle = try thirdRuntime.makeInstance(scriptName: "ChildDefault")
        #expect(Support.value(thirdRuntime.invoke("Pick", on: thirdHandle)) == .integer(3))

        let childNoPick = object(
            "ChildNoPick",
            parent: "ParentWithoutActive",
            automaticState: "Active",
            states: [Support.state(functions: [])]
        )
        let fourthRuntime = PapyrusRuntime(
            files: [PexFixture.runtimeFile(objects: [childNoPick, parentWithoutActive])]
        )
        let fourthHandle = try fourthRuntime.makeInstance(scriptName: "ChildNoPick")
        #expect(Support.value(fourthRuntime.invoke("Pick", on: fourthHandle)) == .integer(4))
    }

    @Test func gotoStateChangesSubsequentMethodLookup() {
        let run = function(
            returnType: "Int",
            locals: [typed("result", "Int")],
            instructions: [
                op(
                    .callMethod,
                    .identifier("GotoState"),
                    .identifier("self"),
                    .identifier("::nonevar"),
                    .integer(1),
                    .string("Other")
                ),
                op(
                    .callMethod,
                    .identifier("Pick"),
                    .identifier("self"),
                    .identifier("result"),
                    .integer(0)
                ),
                op(.returnValue, .identifier("result"))
            ]
        )
        let script = object(
            "StateScript",
            automaticState: "",
            states: [
                Support.state(functions: [("Run", run), ("Pick", returning(1))]),
                Support.state("Other", functions: [("Pick", returning(9))])
            ]
        )
        let (runtime, handle) = Support.runtime(objects: [script])
        #expect(Support.value(runtime.invoke("Run", on: handle)) == .integer(9))
        #expect(runtime.instance(for: handle)?.activeState == "Other")
    }

    @Test func latentNativeSuspendsAndResumesTheSameFrame() {
        let dispatch = PapyrusRecordingNativeDispatch(queuedResults: [.suspended])
        let run = function(
            returnType: "Int",
            locals: [typed("result", "Int")],
            instructions: [
                op(
                    .callStatic,
                    .identifier("SyntheticLatent"),
                    .identifier("Wait"),
                    .identifier("result"),
                    .integer(0)
                ),
                op(.returnValue, .identifier("result"))
            ]
        )
        let script = object(
            "LatentScript",
            states: [Support.state(functions: [("Run", run)])]
        )
        let (runtime, handle) = Support.runtime(
            objects: [script],
            nativeDispatch: dispatch
        )
        let first = runtime.invoke("Run", on: handle)
        guard case let .suspended(call) = first else {
            Issue.record("Expected a suspended Papyrus call")
            return
        }
        #expect(call.nativeCall.qualifiedName == "SyntheticLatent.Wait")
        #expect(Support.value(runtime.resume(call, returning: .integer(17))) == .integer(17))
        #expect(Support.fault(runtime.resume(call, returning: .integer(18))) == .invalidResume)
        #expect(runtime.tally.suspensionTotal == 1)
    }

    @Test func nativeRecorderIsBoundedAndTallied() {
        let dispatch = PapyrusRecordingNativeDispatch(callLimit: 1)
        let run = function(
            returnType: "None",
            instructions: [
                op(
                    .callStatic,
                    .identifier("Debug"),
                    .identifier("First"),
                    .identifier("::nonevar"),
                    .integer(0)
                ),
                op(
                    .callStatic,
                    .identifier("Debug"),
                    .identifier("Second"),
                    .identifier("::nonevar"),
                    .integer(0)
                ),
                op(.returnValue, .null)
            ]
        )
        let script = object(
            "NativeScript",
            states: [Support.state(functions: [("Run", run)])]
        )
        let (runtime, handle) = Support.runtime(
            objects: [script],
            nativeDispatch: dispatch
        )
        _ = runtime.invoke("Run", on: handle)
        #expect(dispatch.callTotal == 2)
        #expect(dispatch.calls.map(\.functionName) == ["Second"])
        #expect(runtime.tally.nativeCallTotal == 2)
    }

    private func returning(_ value: Int32) -> PexFunction {
        function(
            returnType: "Int",
            instructions: [op(.returnValue, .integer(value))]
        )
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

    private func object(
        _ name: String,
        parent: String = "",
        automaticState: String = "",
        variables: [PexVariable] = [],
        states: [PexState]
    ) -> PexObject {
        PexFixture.runtimeObject(
            name: name,
            parent: parent,
            automaticState: automaticState,
            variables: variables,
            states: states
        )
    }

    private func typed(_ name: String, _ type: String) -> PexTypedName {
        PexTypedName(name: name, typeName: type)
    }

    private func op(_ opcode: PexOpcode, _ operands: PexValue...) -> PexInstruction {
        PexInstruction(opcode: opcode, operands: operands)
    }
}
