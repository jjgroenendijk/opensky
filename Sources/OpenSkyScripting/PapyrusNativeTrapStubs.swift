// Traced stubs for the trap census natives the engine cannot run yet: Havok motion
// and impulses, destruction, controller shakes, sounds, and animation
// variables. Each answers the type's empty value and counts as `.stubbed`.

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
        TrapStub("ObjectReference", "SetMotionType", .none),
        TrapStub("ObjectReference", "Reset", .none),
        TrapStub("ObjectReference", "BlockActivation", .none),
        TrapStub("ObjectReference", "SetAnimationVariableFloat", .none),
        TrapStub("ObjectReference", "GetAnimationVariableFloat", .float(0)),
        TrapStub("ObjectReference", "ClearDestruction", .none),
        TrapStub("ObjectReference", "DamageObject", .none),
        TrapStub("ObjectReference", "SetDestroyed", .none),
        TrapStub("ObjectReference", "GetCurrentDestructionStage", .integer(0)),
        TrapStub("ObjectReference", "CreateDetectionEvent", .none),
        TrapStub("ObjectReference", "SetActorCause", .none),
        TrapStub("ObjectReference", "CalculateEncounterLevel", .integer(1)),
        TrapStub("ObjectReference", "GetActorOwner", .none),
        TrapStub("ObjectReference", "GetFactionOwner", .none),
        TrapStub("ObjectReference", "GetParentCell", .none),
        TrapStub("ObjectReference", "AddItem", .none),
        TrapStub("ObjectReference", "InterruptCast", .none),
        TrapStub("ObjectReference", "Say", .none),
        TrapStub("Weapon", "Fire", .none),
        TrapStub("Sound", "Play", .integer(0)),
        TrapStub("EffectShader", "Play", .none),
        TrapStub("Game", "ShakeController", .none),
        TrapStub("Form", "HasKeyword", .boolean(false)),
        TrapStub("FormList", "HasForm", .boolean(false)),
        TrapStub("Actor", "GetEquippedItemType", .integer(0)),
        TrapStub("Cell", "IsAttached", .boolean(true))
    ]

    /// OpenSky plays no object behavior graph, so no animation event arrives. A trap loops
    /// on this wait while its cell is loaded; an instant answer would spin that loop.
    static let animationEventWaitSeconds = 1.0

    static func installTrapStubs(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "ObjectReference",
            functionName: "WaitForAnimationEvent"
        ) { call, context in
            context.log.append("Paced \(call.qualifiedName)")
            return .suspended(.realSecondsAnswering(animationEventWaitSeconds, .boolean(true)))
        })
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
