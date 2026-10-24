// Lookups the shipped scripts rely on: a variable a parent declares, a global
// script no attached script names, and a method of a receiver with no script.

import Foundation
@testable import OpenSkyFormatsPEX
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusScriptLookupTests {
    /// `Tripwire` declares no variables and plays `TrapTriggerBase`'s sound.
    @Test func aParentVariableNamesTheReceiverType() throws {
        let parent = PexFixture.runtimeObject(
            name: "ParentScript",
            variables: [PexVariable(
                name: "::sound_var", typeName: "Sound", userFlags: 0, initialValue: .null
            )],
            states: []
        )
        let run = PexFixture.runtimeFunction(instructions: [
            PapyrusTestSupport.instruction(
                .callMethod, .identifier("Play"), .identifier("::sound_var"),
                .identifier("::NoneVar"), .integer(0)
            )
        ])
        let child = PexFixture.runtimeObject(
            name: "ChildScript",
            parent: "ParentScript",
            states: [PapyrusTestSupport.state(functions: [("Run", run)])]
        )
        let dispatch = PapyrusRecordingNativeDispatch()
        let runtime = PapyrusRuntime(
            files: [PexFixture.runtimeFile(objects: [child, parent])],
            nativeDispatch: dispatch
        )
        let handle = try runtime.makeInstance(
            scriptName: "ChildScript",
            initialValues: ["::sound_var": .object(PapyrusObjectHandle(900))]
        )
        _ = runtime.invoke("Run", on: handle)
        #expect(dispatch.calls.last?.qualifiedName == "Sound.Play")
    }

    /// `DartTrap` counts its ports through the global `custom.countLinks`.
    @Test func aStaticCallLoadsItsGlobalScript() throws {
        let count = PexFixture.runtimeFunction(
            returnType: "Int",
            flags: [.global],
            instructions: [PapyrusTestSupport.instruction(.returnValue, .integer(7))]
        )
        let helper = PexFixture.runtimeObject(
            name: "Helper",
            states: [PapyrusTestSupport.state(functions: [("Count", count)])]
        )
        let run = PexFixture.runtimeFunction(
            returnType: "Int",
            locals: [PexTypedName(name: "result", typeName: "Int")],
            instructions: [
                PapyrusTestSupport.instruction(
                    .callStatic, .identifier("Helper"), .identifier("Count"),
                    .identifier("result"), .integer(0)
                ),
                PapyrusTestSupport.instruction(.returnValue, .identifier("result"))
            ]
        )
        let caller = PexFixture.runtimeObject(
            name: "Caller",
            states: [PapyrusTestSupport.state(functions: [("Run", run)])]
        )
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [caller], nativeDispatch: PapyrusRecordingNativeDispatch()
        )
        world.scriptProvider = { name in
            PapyrusRuntime.matches(name, "Helper") ? PexFixture.runtimeFile(objects: [helper]) : nil
        }
        let handle = try world.runtime.makeInstance(scriptName: "Caller")
        #expect(PapyrusTestSupport.value(world.runtime.invoke("Run", on: handle)) == .integer(7))
    }

    /// `PlayerSleepQuestScript` calls `IsInInterior`, which `ObjectReference.psc` writes
    /// in Papyrus, on the player, who has no script instance.
    @Test func aReceiverWithoutAScriptRunsAWrapperOfItsType() throws {
        let wrapper = PexFixture.runtimeFunction(returnType: "Bool", instructions: [
            PapyrusTestSupport.instruction(
                .callMethod, .identifier("GetParentCell"), .identifier("self"),
                .identifier("::NoneVar"), .integer(0)
            ),
            PapyrusTestSupport.instruction(.returnValue, .boolean(true))
        ])
        let base = PexFixture.runtimeObject(
            name: "ObjectReference",
            states: [PapyrusTestSupport.state(functions: [("IsInInterior", wrapper)])]
        )
        let dispatch = try runLazily(base, calling: "IsInInterior", on: "ObjectReference")
        #expect(dispatch.result == .boolean(true))
        #expect(dispatch.calls.last?.functionName == "GetParentCell")
        #expect(dispatch.calls.last?.receiver == PapyrusObjectHandle(900))
    }

    /// `Location.HasKeyword` is `Form`'s native; the chain loads when it is first used.
    @Test func aNativeOfALazilyLoadedParentKeepsItsScriptName() throws {
        let native = PexFixture.runtimeFunction(
            returnType: "Bool",
            flags: [.native],
            instructions: []
        )
        let form = PexFixture.runtimeObject(
            name: "Form", states: [PapyrusTestSupport.state(functions: [("HasKeyword", native)])]
        )
        let location = PexFixture.runtimeObject(name: "Location", parent: "Form", states: [])
        let dispatch = try runLazily(location, form, calling: "HasKeyword", on: "Location")
        #expect(dispatch.calls.last?.qualifiedName == "Form.HasKeyword")
    }

    private func runLazily(
        _ library: PexObject...,
        calling function: String,
        on type: String
    ) throws -> (result: PapyrusValue?, calls: [PapyrusNativeCall]) {
        let run = PexFixture.runtimeFunction(
            returnType: "Bool",
            locals: [PexTypedName(name: "result", typeName: "Bool")],
            instructions: [
                PapyrusTestSupport.instruction(
                    .callMethod, .identifier(function), .identifier("target"),
                    .identifier("result"), .integer(0)
                ),
                PapyrusTestSupport.instruction(.returnValue, .identifier("result"))
            ]
        )
        let caller = PexFixture.runtimeObject(
            name: "Caller",
            variables: [PexVariable(
                name: "target",
                typeName: type,
                userFlags: 0,
                initialValue: .null
            )],
            states: [PapyrusTestSupport.state(functions: [("Run", run)])]
        )
        let dispatch = PapyrusRecordingNativeDispatch()
        let world = PapyrusWorldFixture.worldRuntime(objects: [caller], nativeDispatch: dispatch)
        world.scriptProvider = { name in
            library.first { PapyrusRuntime.matches($0.name, name) }.map {
                PexFixture.runtimeFile(objects: [$0])
            }
        }
        let handle = try world.runtime.makeInstance(
            scriptName: "Caller", initialValues: ["target": .object(PapyrusObjectHandle(900))]
        )
        let result = PapyrusTestSupport.value(world.runtime.invoke("Run", on: handle))
        return (result, dispatch.calls)
    }
}
