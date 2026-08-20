// The character-level natives (issue #499, roadmap item 20.6): `Actor.GetLevel`
// and the two SKSE perk-point functions, over 20.6's level runtime.
//
// Policy is the perk and skill families', unchanged: `self` arrives as
// `PapyrusNativeCall.receiver` and becomes a `ReferenceKey`, a session with no
// progression is a failure with a reason rather than a guess, and the
// interpreter substitutes the call's declared default so the script keeps
// running.
//
// ## Why two of the three are SKSE functions
//
// The perk-point pool has no vanilla Papyrus surface at all; the Creation Kit
// wiki declares `GetPerkPoints`, `SetPerkPoints` and `ModPerkPoints` as SKSE
// additions to the `Game` script. OpenSky implements the two the pool needs to
// be readable and writable and states the third's absence rather than guessing
// at it, which is the same rule the rest of the native surface follows. The
// script-level half of SKSE compatibility is a stated goal
// (docs/engine/papyrus-vm.md); the binary half is not.
//
// `Game.GetPerk` is *not* here. It resolves an editor id to a PERK form, which
// is a record lookup rather than a progression question, and it belongs with
// whichever item gives `Game` a form lookup.
//
// Documented in docs/engine/papyrus-vm.md and docs/engine/character-leveling.md.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    static func installLevel(into registry: inout PapyrusNativeRegistry) {
        // "Gets the actor's current level." — "int Function GetLevel() native"
        // (<https://www.creationkit.com/index.php?title=GetLevel_-_Actor>)
        // An NPC answers its derived level, the player answers its character
        // level, and both come from the one baseline every other actor-value
        // read already goes through.
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "GetLevel"
        ) { call, context in
            guard
                let actor = actorTarget(call, context),
                let state = actor.world.actorState(for: actor.key)
            else {
                return needsActor(call)
            }
            return .returned(.integer(Int32(clamping: state.level)))
        })

        // "Returns the number of perk points available to the player. (This
        // function requires SKSE)" — "Int Function GetPerkPoints() native"
        // (<https://ck.uesp.net/wiki/GetPerkPoints_-_Game>)
        registry.register(PapyrusNativeFunction(
            scriptName: "Game",
            functionName: "GetPerkPoints"
        ) { call, context in
            guard let world = context.world, let points = world.playerPerkPoints() else {
                return needsProgress(call)
            }
            return .returned(.integer(Int32(clamping: points)))
        })

        // "Modifies the number of perk points available to the player by the
        // specified amount. (This function requires SKSE)" — "Function
        // ModPerkPoints(Int PerkPoints) native", and "Final values can not
        // exceed 255" (<https://ck.uesp.net/wiki/ModPerkPoints_-_Game>), which
        // is the clamp `PlayerProgressState` applies.
        registry.register(PapyrusNativeFunction(
            scriptName: "Game",
            functionName: "ModPerkPoints"
        ) { call, context in
            guard let delta = integer(call, at: 0) else {
                return failure(call, "ModPerkPoints needs a perk-point count")
            }
            guard
                let world = context.world,
                world.modifyPlayerPerkPoints(by: Int(delta)) != nil
            else {
                return needsProgress(call)
            }
            return .returned(.none)
        })
    }

    /// The one failure the two perk-point natives return when the session runs
    /// no character leveling: nothing was read or written, and saying so is
    /// better than a script that believes it granted a perk point.
    private static func needsProgress(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        failure(call, "\(call.functionName) needs a session with character leveling")
    }
}
