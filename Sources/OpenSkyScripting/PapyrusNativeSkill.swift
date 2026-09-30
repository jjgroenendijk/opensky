// The skill natives: `Game.AdvanceSkill` and `Game.IncrementSkill`, which act on
// the player only (<https://ck.uesp.net/wiki/AdvanceSkill_-_Game>).
// `AdvanceSkill` passes skill use, which the AVIF multipliers convert;
// `IncrementSkill` passes one whole point. Both run the same path as a landed hit.
//
// Documented in docs/engine/papyrus-activation.md and docs/engine/skill-advancement.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    public static func installSkill(into registry: inout PapyrusNativeRegistry) {
        // "Function AdvanceSkill(string asSkillName, float afMagnitude) native
        // global". The page requires a positive magnitude; a zero or negative
        // one is refused here rather than quietly treated as a use, which is
        // what the runtime does with an empty amount anyway.
        registry.register(PapyrusNativeFunction(
            scriptName: "Game",
            functionName: "AdvanceSkill"
        ) { call, context in
            skillCall(call, context) { world, index in
                guard let magnitude = float(call, at: 1), magnitude > 0 else {
                    return failure(call, "AdvanceSkill needs a positive magnitude")
                }
                guard world.advancePlayerSkill(.advance, at: index, by: magnitude) else {
                    return needsProgression(call)
                }
                return .returned(.none)
            }
        })

        // "Function IncrementSkill(string asSkillName) native global".
        registry.register(PapyrusNativeFunction(
            scriptName: "Game",
            functionName: "IncrementSkill"
        ) { call, context in
            skillCall(call, context) { world, index in
                guard world.advancePlayerSkill(.increment, at: index, by: 1) else {
                    return needsProgression(call)
                }
                return .returned(.none)
            }
        })
    }

    /// The one failure both natives return when the session runs no
    /// progression: nothing advanced, and saying so is better than a script
    /// that believes it taught the player something.
    private static func needsProgression(
        _ call: PapyrusNativeCall
    ) -> PapyrusNativeResult {
        failure(call, "\(call.functionName) needs a session with skill advancement")
    }

    /// Resolves the world and the skill name. Names use the record vocabulary
    /// Papyrus speaks, so `"Marksman"` means `Archery`
    /// (`ActorValueIdentity.recordNameAliases`). A name outside the eighteen
    /// skills is refused.
    private static func skillCall(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext,
        body: (any PapyrusWorldBridge, Int32) -> PapyrusNativeResult
    ) -> PapyrusNativeResult {
        guard let world = context.world else {
            return failure(call, "\(call.functionName) needs a world runtime")
        }
        guard
            let name = string(call, at: 0),
            let index = ActorValueIdentity.index(recordName: name),
            ActorValueIdentity.isSkill(index: index)
        else {
            return failure(call, "\(call.functionName) needs a skill name")
        }
        return body(world, index)
    }
}
