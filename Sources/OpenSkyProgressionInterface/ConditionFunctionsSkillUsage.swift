// The skill-use condition functions of the `Mod Skill Use` entry point, from xEdit
// dev-4.1.6 Core/wbDefinitionsTES5.pas: 681 `EPMagic_IsAdvanceSkill` (ptActorValue),
// 691 `EPModSkillUsage_AdvanceObjectHasKeyword` (ptKeyword) and 692
// `EPModSkillUsage_IsAdvanceAction` (ptPlayerAction). The Guardian Stone perks use 681.
// See docs/engine/skill-advancement.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

/// The use being credited. Empty outside a skill-use evaluation.
nonisolated public struct SkillUsageConditionResolution: Sendable {
    public static let empty = SkillUsageConditionResolution(skill: nil)

    /// Nil when no use is being credited.
    public let skill: Int32?
    public let action: SkillAdvanceAction
    public let object: ResolvedFormID?

    public init(
        skill: Int32?,
        action: SkillAdvanceAction = .normalUsage,
        object: ResolvedFormID? = nil
    ) {
        self.skill = skill
        self.action = action
        self.object = object
    }
}

nonisolated extension SkillUsageConditionResolution: ConditionResolution {}

nonisolated extension ConditionContext {
    public var skillUsage: SkillUsageConditionResolution {
        get { self[resolution: SkillUsageConditionResolution.self] }
        set { self[resolution: SkillUsageConditionResolution.self] = newValue }
    }
}

nonisolated extension ConditionFunctions {
    public static func installSkillUsage(_ registry: inout ConditionFunctionRegistry) {
        // `doomWarriorPerk` passes when the skill is one of five combat skills,
        // each written as `== 1` in an OR group.
        registry.register(ConditionFunction(
            index: 681,
            name: "EPMagic_IsAdvanceSkill",
            parameter1: .integer
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(681))
            }
            guard let skill = call.context.skillUsage.skill else {
                return .failure(.unavailableData(.skillUsage))
            }
            return .success(Self.isTrue(skill == parameter.asInt32))
        })
        registry.register(ConditionFunction(
            index: 691,
            name: "EPModSkillUsage_AdvanceObjectHasKeyword",
            parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(691))
            }
            guard
                call.context.skillUsage.skill != nil,
                let object = call.context.skillUsage.object,
                let store = call.context.data.keywords,
                let sourcePlugin = call.context.data.sourcePlugin,
                let keyword = store.resolvedID(parameter.asFormID, fromPlugin: sourcePlugin),
                let answer = store.hasKeyword(keyword, on: object)
            else { return .failure(.unavailableData(.skillUsage)) }
            return .success(Self.isTrue(answer))
        })
        registry.register(ConditionFunction(
            index: 692,
            name: "EPModSkillUsage_IsAdvanceAction",
            parameter1: .integer
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(692))
            }
            guard call.context.skillUsage.skill != nil else {
                return .failure(.unavailableData(.skillUsage))
            }
            return .success(Self
                .isTrue(call.context.skillUsage.action.rawValue == parameter.asInt32))
        })
    }
}
