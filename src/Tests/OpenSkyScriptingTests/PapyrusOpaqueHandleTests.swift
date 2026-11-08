import Foundation
@testable import OpenSkyFormatsPEX
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

@MainActor
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

    @Test func anOpaqueReferenceRunsAGetterOfItsType() throws {
        let getter = PexFixture.runtimeFunction(
            returnType: "Int",
            instructions: [op(.returnValue, .integer(4))]
        )
        let constant = PexProperty(
            name: "Motion_Keyframed",
            typeName: "Int",
            documentation: "",
            userFlags: 0,
            flags: [.readable],
            automaticVariableName: nil,
            readHandler: getter,
            writeHandler: nil
        )
        let base = PexFixture.runtimeObject(
            name: "ObjectReference",
            properties: [constant],
            states: []
        )
        let function = PexFixture.runtimeFunction(
            returnType: "Int",
            locals: [PexTypedName(name: "motion", typeName: "Int")],
            instructions: [
                op(
                    .propertyGet,
                    .identifier("Motion_Keyframed"),
                    .identifier("target"),
                    .identifier("motion")
                ),
                op(.returnValue, .identifier("motion"))
            ]
        )
        let script = PexFixture.runtimeObject(
            name: "OpaqueScript",
            variables: [PexVariable(
                name: "target",
                typeName: "ObjectReference",
                userFlags: 0,
                initialValue: .null
            )],
            states: [Support.state(functions: [("Run", function)])]
        )
        let runtime = PapyrusRuntime(files: [PexFixture.runtimeFile(objects: [script, base])])
        let instance = try runtime.makeInstance(
            scriptName: script.name,
            initialValues: ["target": .object(PapyrusObjectHandle(900))]
        )
        #expect(Support.value(runtime.invoke("Run", on: instance)) == .integer(4))
    }

    /// A global has no script instance, yet `debugOn.Value = 0` runs the setter of
    /// `GlobalVariable` instead of faulting.
    @Test func anOpaqueFormRunsASetterOfItsType() throws {
        let setter = PexFixture.runtimeFunction(
            returnType: "None",
            parameters: [PexTypedName(name: "afValue", typeName: "Float")],
            instructions: [op(.returnValue, .null)]
        )
        let value = PexProperty(
            name: "Value",
            typeName: "Float",
            documentation: "",
            userFlags: 0,
            flags: [.readable, .writable],
            automaticVariableName: nil,
            readHandler: nil,
            writeHandler: setter
        )
        let global = PexFixture.runtimeObject(
            name: "GlobalVariable",
            properties: [value],
            states: []
        )
        let function = PexFixture.runtimeFunction(
            returnType: "Int",
            instructions: [
                op(.propertySet, .identifier("Value"), .identifier("debugOn"), .float(0)),
                op(.returnValue, .integer(1))
            ]
        )
        let script = PexFixture.runtimeObject(
            name: "OpaqueScript",
            variables: [PexVariable(
                name: "debugOn",
                typeName: "GlobalVariable",
                userFlags: 0,
                initialValue: .null
            )],
            states: [Support.state(functions: [("Run", function)])]
        )
        let runtime = PapyrusRuntime(files: [PexFixture.runtimeFile(objects: [script, global])])
        let instance = try runtime.makeInstance(
            scriptName: script.name,
            initialValues: ["debugOn": .object(PapyrusObjectHandle(900))]
        )
        #expect(Support.value(runtime.invoke("Run", on: instance)) == .integer(1))
    }

    /// A stopped quest's handle has no instance until a script uses it. Reading a
    /// property through it reaches the instance the runtime attaches then.
    @Test func aPropertyReadReachesTheInstanceAttachedOnUse() throws {
        let stored = PexProperty(
            name: "SolitudeHouseVar",
            typeName: "Int",
            documentation: "",
            userFlags: 0,
            flags: [.readable, .writable, .automatic],
            automaticVariableName: "::SolitudeHouseVar_var",
            readHandler: nil,
            writeHandler: nil
        )
        let quest = PexFixture.runtimeObject(
            name: "ProbeHouseScript",
            variables: [PexVariable(
                name: "::SolitudeHouseVar_var", typeName: "Int", userFlags: 0,
                initialValue: .integer(2)
            )],
            properties: [stored],
            states: []
        )
        let function = PexFixture.runtimeFunction(
            returnType: "Int",
            locals: [PexTypedName(name: "owned", typeName: "Int")],
            instructions: [
                op(
                    .propertyGet,
                    .identifier("SolitudeHouseVar"),
                    .identifier("house"),
                    .identifier("owned")
                ),
                op(.returnValue, .identifier("owned"))
            ]
        )
        let script = PexFixture.runtimeObject(
            name: "OpaqueScript",
            variables: [PexVariable(
                name: "house",
                typeName: "ProbeHouseScript",
                userFlags: 0,
                initialValue: .null
            )],
            states: [Support.state(functions: [("Run", function)])]
        )
        let runtime = PapyrusRuntime(files: [PexFixture.runtimeFile(objects: [script, quest])])
        let attached = try runtime.makeInstance(scriptName: quest.name, initialValues: [:])
        runtime
            .siblingInstance = { handle, _ in handle == PapyrusObjectHandle(900) ? attached : nil }
        let reader = try runtime.makeInstance(
            scriptName: script.name,
            initialValues: ["house": .object(PapyrusObjectHandle(900))]
        )
        #expect(Support.value(runtime.invoke("Run", on: reader)) == .integer(2))
    }

    private func op(_ opcode: PexOpcode, _ operands: PexValue...) -> PexInstruction {
        PexInstruction(opcode: opcode, operands: operands)
    }
}
