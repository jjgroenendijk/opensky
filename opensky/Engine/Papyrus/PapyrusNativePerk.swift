// The perk natives (issue #497, roadmap item 20.4): the `Actor` perk family
// over 20.4's perk runtime.
//
// Policy is the `Actor` and spell families', unchanged: `self` arrives as
// `PapyrusNativeCall.receiver` and becomes a `ReferenceKey`; a headless
// runtime, a handle with no world identity, or a session with no perk data is a
// failure with a reason rather than a guess, and the interpreter substitutes
// the call's declared default so the script keeps running.
//
// Three natives, which is the whole `Actor` perk surface the Creation Kit wiki
// declares. `Game.GetPerk` and the perk-point functions belong to the perk tree
// and the level-up screen, which are items 20.6 and 20.7.
//
// Documented in docs/engine/papyrus-vm.md and docs/engine/perks.md.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    static func installPerk(into registry: inout PapyrusNativeRegistry) {
        // "Adds the specified perk to this actor."
        // (<https://ck.uesp.net/wiki/AddPerk_-_Actor>) The page notes the
        // function does not spend a perk point, which is what makes it the
        // right door for a quest reward; spending is item 20.6's.
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
        body: ((world: PapyrusWorldAccess, key: ReferenceKey), ReferenceKey)
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
