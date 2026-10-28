// Traced stubs for natives whose engine system OpenSky does not have yet: Havok
// constraints, Bink movies, the title sequence, and eye textures.
// Each answers the type's empty value and counts as `.stubbed`; each gap has an issue.

import Foundation
import OpenSkyScriptingInterface

private struct EngineStub {
    let script: String
    let name: String
    let answer: PapyrusValue

    init(_ script: String, _ name: String, _ answer: PapyrusValue) {
        self.script = script
        self.name = name
        self.answer = answer
    }
}

extension PapyrusNativeFunctions {
    private static let engineStubs: [EngineStub] = [
        EngineStub("Actor", "SetEyeTexture", .none),
        EngineStub("Game", "AddHavokBallAndSocketConstraint", .boolean(false)),
        EngineStub("Game", "RemoveHavokConstraints", .boolean(false)),
        EngineStub("Game", "PlayBink", .none),
        EngineStub("Game", "StartTitleSequence", .none)
    ]

    static func installEngineStubs(into registry: inout PapyrusNativeRegistry) {
        for stub in engineStubs {
            registry.register(PapyrusNativeFunction(
                scriptName: stub.script, functionName: stub.name
            ) { call, context in
                context.log.append("Stubbed \(call.qualifiedName)")
                return .deviated(stub.answer, .stubbed)
            })
        }
    }
}
