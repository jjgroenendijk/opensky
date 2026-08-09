// Dialogue-demanded condition functions (issue #426), split out of
// `ConditionFunctions` the way `ConditionFunctionsQuest` is.
//
// These three come off the demand list the 17.1 sweep measured rather than off
// a guess about what dialogue needs. Across the 55,641 conditions attached to
// the INFO records of `Skyrim.esm`, the two heaviest functions the registry did
// not hold were stored index 426 with 6,324 conditions and stored index 566
// with 5,320; index 249 adds 428. Every other unregistered index on that list
// belongs to a subsystem that is not dialogue's — factions, inventory,
// locations, keywords, Papyrus quest variables — and each is honest work for
// the milestone that owns it rather than something to fake here.
//
// Indices below are the raw stored numbers; the Creation Kit spells each 4096
// higher. They come from xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, whose
// condition-function table lists:
//
//   (Index: 249; Name: 'IsInDialogueWithPlayer')
//   (Index: 426; Name: 'GetIsVoiceType'; ParamType1: ptVoiceType)
//   (Index: 566; Name: 'GetIsAliasRef'; ParamType1: ptAlias)
//
// Return semantics come from the Creation Kit wiki's condition-function pages,
// cited at each registration.

import Foundation

nonisolated extension ConditionFunctions {
    static func installDialogue(_ registry: inout ConditionFunctionRegistry) {
        // "Returns true if the actor's voice type matches the specified voice
        // type." (<https://ck.uesp.net/wiki/GetIsVoiceType>) Parameter 1 is
        // `ptVoiceType`, a VTYP FormID.
        //
        // An actor this session resolved no voice type for is
        // `.unavailableDialogue` rather than 0. "This actor's voice is not the
        // one you named" and "nothing here knows this actor's voice" are
        // different answers, and only one of them is real — the same rule the
        // actor seam applies to a missing draw state.
        registry.register(ConditionFunction(
            index: 426,
            name: "GetIsVoiceType",
            parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(426))
            }
            return call.referenceKey().flatMap { key in
                guard let voice = call.context.dialogue.voiceType(of: key) else {
                    return .failure(.unavailableDialogue)
                }
                return .success(Self.isTrue(voice == parameter.asFormID))
            }
        })

        // "Returns true if the reference is the reference filling the specified
        // alias." (<https://ck.uesp.net/wiki/GetIsAliasRef>) Parameter 1 is
        // `ptAlias`, an alias *number* on the quest the condition was read
        // from, which for a dialogue condition is the quest that owns the topic
        // — `ConditionContext.aliasQuest`, the field whose doc comment has
        // anticipated this call since issue #251.
        //
        // A context with no quest scope, or an alias nothing has filled, is a
        // reason-tagged failure rather than 0, because "this reference is not
        // the one in that alias" is a claim that needs a filled alias to be
        // true or false about.
        registry.register(ConditionFunction(
            index: 566,
            name: "GetIsAliasRef",
            parameter1: .integer
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(566))
            }
            guard let filled = call.aliasReference(parameter) else {
                return .failure(.unresolvedParameter(566))
            }
            return call.referenceKey().map { Self.isTrue($0 == filled) }
        })

        // "Returns true if the actor is currently in dialogue with the player."
        // (<https://ck.uesp.net/wiki/IsInDialogueWithPlayer>) The live
        // conversation is exactly what `DialogueResolution` carries, so this is
        // a pure read of that seam.
        //
        // A context with no conversation open answers 0 rather than failing:
        // "nobody is talking to the player" is a real answer that an empty seam
        // states correctly, unlike an unknown voice type.
        registry.register(ConditionFunction(
            index: 249,
            name: "IsInDialogueWithPlayer"
        ) { call in
            call.referenceKey().map {
                Self.isTrue(call.context.dialogue.isInDialogueWithPlayer($0))
            }
        })
    }
}
