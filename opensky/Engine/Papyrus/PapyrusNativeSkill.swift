// The skill natives (issue #498, roadmap item 20.5): `Game.AdvanceSkill` and
// `Game.IncrementSkill` over 20.5's advancement runtime.
//
// Both are global functions on `Game` and both act on the player alone, which
// the wiki states rather than implies: "Advances the progress of the provided
// Skill by the given amount (for the player only)"
// (<https://ck.uesp.net/wiki/AdvanceSkill_-_Game>) and "Advances the provided
// Skill by the one point (for the player only)"
// (<https://ck.uesp.net/wiki/IncrementSkill_-_Game>). So neither takes a
// receiver and neither needs one.
//
// The difference between them is the unit, and it is the whole reason they are
// two functions: `AdvanceSkill` hands over skill *use*, which the skill's own
// AVIF multipliers then convert and which may or may not reach the next
// threshold — "This is in Skill Usage amounts, so it will count towards skill
// progression but won't necessarily change the Skill itself" — while
// `IncrementSkill` hands over a whole point. Both run the same path a swing
// does, so a scripted advance and a landed blow cannot drift apart.
//
// Policy is the perk family's, unchanged: a session with no progression runtime
// is a failure with a reason rather than a silent no-op, and the interpreter
// substitutes the call's declared default so the script keeps running.
//
// Documented in docs/engine/papyrus-vm.md and docs/engine/skill-advancement.md.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    static func installSkill(into registry: inout PapyrusNativeRegistry) {
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

    /// Resolves the world and the skill name both natives start with.
    ///
    /// The name is read with the *record* vocabulary, which is what Papyrus
    /// speaks: the wiki's own example is `Game.AdvanceSkill("Marksman", 50.0)`,
    /// and `Marksman` is the editor-id spelling of `Archery`
    /// (`ActorValueIdentity.recordNameAliases`). A name that is not one of the
    /// eighteen skills is a refusal rather than a write to a neighbouring actor
    /// value.
    private static func skillCall(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext,
        body: (PapyrusWorldAccess, Int32) -> PapyrusNativeResult
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
