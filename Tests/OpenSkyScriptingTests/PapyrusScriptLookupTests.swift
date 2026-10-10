// Lookups the shipped scripts rely on: a variable a parent declares, and a global
// script no attached script names.

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
}
