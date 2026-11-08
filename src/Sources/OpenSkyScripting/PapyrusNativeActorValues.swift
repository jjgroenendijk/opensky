// The actor-value write natives: `SetActorValue`, `ModActorValue` and
// `ForceActorValue`. Registration checks the arguments;
// `ActorValueRuntimeGeneral` decides what a slot means.
//
// Documented in docs/engine/actor-value-store.md and docs/engine/papyrus-actor-natives.md.

import Foundation
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    /// `SetActorValue`, `ModActorValue` and `ForceActorValue`, each `(string, float)`.
    /// `SetAV`, `ModAV` and `ForceAV` are Papyrus wrappers, so they need no entry.
    /// A negative amount passes through, unlike `DamageActorValue`: the wiki's
    /// `ModActorValue` example lowers health by -10
    /// (<https://ck.uesp.net/wiki/ModActorValue_-_Actor>).
    public static func installActorValueWriteNatives(into registry: inout PapyrusNativeRegistry) {
        for write in PapyrusActorValueWrite.allCases {
            registry.register(PapyrusNativeFunction(
                scriptName: "Actor",
                functionName: write.rawValue
            ) { call, context in
                guard let actor = actorTarget(call, context) else {
                    return needsActor(call)
                }
                guard let index = actorValueIndex(call, at: 0) else {
                    return unknownActorValue(call, at: 0)
                }
                guard let value = float(call, at: 1), value.isFinite else {
                    return failure(call, "\(write.rawValue) needs a finite value")
                }
                guard
                    actor.world.writeActorValue(write, at: index, to: value, on: actor.key) != nil
                else {
                    return needsActor(call)
                }
                return .returned(.none)
            })
        }
    }
}
