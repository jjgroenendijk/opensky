// The perk natives: the whole `Actor` perk surface the Creation Kit wiki
// declares. A missing world or perk data is a failure with a reason.
//
// Documented in docs/engine/papyrus-activation.md and docs/engine/perks.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    public static func installPerk(into registry: inout PapyrusNativeRegistry) {
        // "Adds the specified perk to this actor."
        // (<https://ck.uesp.net/wiki/AddPerk_-_Actor>) It spends no perk point, so it
        // fits a quest reward.
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "AddPerk"
        ) { call, context in
            perkTarget(call, context) { actor, perk in
                .returned(.boolean(actor.world.addPerk(perk, to: actor.key)))
            }
        })

        // "Removes the specified perk from this actor."
        // (<https://ck.uesp.net/wiki/RemovePerk_-_Actor>)
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "RemovePerk"
        ) { call, context in
            perkTarget(call, context) { actor, perk in
                .returned(.boolean(actor.world.removePerk(perk, from: actor.key)))
            }
        })

        // "Returns whether this actor has the specified perk or not."
        // (<https://ck.uesp.net/wiki/HasPerk_-_Actor>)
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "HasPerk"
        ) { call, context in
            perkTarget(call, context) { actor, perk in
                guard let owns = actor.world.hasPerk(perk, on: actor.key) else {
                    return failure(
                        call,
                        "HasPerk needs a session with a perk runtime"
                    )
                }
                return .returned(.boolean(owns))
            }
        })
    }

    /// An `Actor` perk native: resolve the receiver and the PERK argument, then
    /// run `body`.
    private static func perkTarget(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext,
        body: ((world: any PapyrusWorldBridge, key: ReferenceKey), ReferenceKey)
            -> PapyrusNativeResult
    ) -> PapyrusNativeResult {
        guard let actor = actorTarget(call, context) else {
            return needsActor(call)
        }
        guard
            let handle = objectArgument(call, at: 0),
            let perk = actor.world.referenceKey(for: handle)
        else {
            return failure(call, "\(call.functionName) needs a perk argument")
        }
        return body(actor, perk)
    }
}
