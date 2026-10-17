// Dialogue condition functions, chosen by demand across the INFO conditions of
// `Skyrim.esm`. Raw stored indices from xEdit dev-4.1.6
// Core/wbDefinitionsTES5.pas: 249 `IsInDialogueWithPlayer`, 426
// `GetIsVoiceType` (ptVoiceType), 566 `GetIsAliasRef` (ptAlias). Return rules
// come from the Creation Kit wiki pages cited at each registration.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension ConditionFunctions {
    public static func installDialogue(_ registry: inout ConditionFunctionRegistry) {
        installDialogueLine(&registry)
        // "Returns true if the actor's voice type matches the specified voice type."
        // A FormList parameter is true when the voice type is in the list.
        // (<https://ck.uesp.net/wiki/GetIsVoiceType>) An actor with no resolved voice
        // type is `.unavailableDialogue`, not 0.
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
                if let inList = Self.isVoice(voice, inList: parameter.asFormID, call.context) {
                    return .success(Self.isTrue(inList))
                }
                return .success(Self.isTrue(voice == parameter.asFormID))
            }
        })

        // "Returns true if the reference is the reference filling the specified alias."
        // (<https://ck.uesp.net/wiki/GetIsAliasRef>) The alias number is on
        // `ConditionContext.aliasQuest`. No quest scope or an unfilled alias is a
        // reason-tagged failure, not 0.
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
        // (<https://ck.uesp.net/wiki/IsInDialogueWithPlayer>) A pure read of
        // `DialogueResolution`; no open conversation answers 0.
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

nonisolated extension ConditionFunctions {
    /// Nil when `list` names no FLST in the context's data seam, so the caller
    /// compares it as a single voice type.
    static func isVoice(
        _ voice: FormID,
        inList list: FormID,
        _ context: ConditionContext
    ) -> Bool? {
        guard
            let lists = context.data.formLists,
            let plugin = context.data.sourcePlugin,
            let listID = lists.resolvedID(list, fromPlugin: plugin),
            lists.formList(listID) != nil,
            let member = lists.resolvedID(voice, fromPlugin: plugin)
        else { return nil }
        return lists.contains(member, in: listID)
    }
}
