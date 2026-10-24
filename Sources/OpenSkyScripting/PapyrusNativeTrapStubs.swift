// Traced stubs for the trap census natives the engine cannot run yet: detection,
// controller shakes, and sounds. Each answers the type's empty value and counts as
// `.stubbed`.

import Foundation
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    /// One stubbed native and the value it answers.
    private struct TrapStub {
        let scriptName: String
        let functionName: String
        let answer: PapyrusValue

        init(_ scriptName: String, _ functionName: String, _ answer: PapyrusValue) {
            self.scriptName = scriptName
            self.functionName = functionName
            self.answer = answer
        }
    }

    private static let trapStubs: [TrapStub] = [
        TrapStub("ObjectReference", "CreateDetectionEvent", .none),
        TrapStub("ObjectReference", "SetActorCause", .none),
        TrapStub("ObjectReference", "CalculateEncounterLevel", .integer(1)),
        TrapStub("ObjectReference", "InterruptCast", .none),
        TrapStub("ObjectReference", "Say", .none),
        TrapStub("Sound", "Play", .integer(0)),
        TrapStub("Sound", "StopInstance", .none),
        TrapStub("Game", "ShakeController", .none),
        TrapStub("Actor", "GetEquippedItemType", .integer(0)),
        TrapStub("Cell", "IsAttached", .boolean(true))
    ]

    static func installTrapStubs(into registry: inout PapyrusNativeRegistry) {
        for stub in trapStubs {
            registry.register(PapyrusNativeFunction(
                scriptName: stub.scriptName,
                functionName: stub.functionName
            ) { call, context in
                context.log.append("Stubbed \(call.qualifiedName)")
                return .deviated(stub.answer, .stubbed)
            })
        }
    }
}
