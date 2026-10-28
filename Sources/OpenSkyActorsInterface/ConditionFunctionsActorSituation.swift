// Actor condition functions over load, fights, and reactions, indices from xEdit
// wbDefinitionsTES5.pas: 734 `IsOverEncumbered`, 645 `GetIsInjured`, 415
// `GetGroupMemberCount`, 697 `IsAttackType`, 247 `GetIsUsedItemType`, 305
// `GetPlayerAction`, 274 `IsSmallBump`, and 642 `GetLastBumpDirection`.
// See docs/engine/condition-functions-world.md#actor-situation.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension ConditionFunctions {
    static func installActorSituation(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(index: 734, name: "IsOverEncumbered") { call in
            call.actorState().flatMap { state in
                guard let isOver = state.isOverEncumbered else {
                    return .failure(.unavailableActorState)
                }
                return .success(Self.isTrue(isOver))
            }
        })
        // Each fighting side is one group. A fighting NPC is in the group of every NPC
        // that fights the player; the player fights alone.
        registry.register(ConditionFunction(index: 415, name: "GetGroupMemberCount") { call in
            call.referenceKey().flatMap { key in
                call.actorState().map { state in
                    guard !state.isDead, state.combatActivity != .notFighting else { return 0 }
                    return key == .player ? 1 : Float(call.context.actors.fightingNonPlayerCount)
                }
            }
        })
        // The CK wiki: the graph's `Injured`, set below the race's injured health share.
        registry.register(ConditionFunction(index: 645, name: "GetIsInjured") { call in
            call.actorState().map { Self.isTrue($0.isInjured) }
        })
        installAttackType(&registry)
        // OpenSky has no item use by an actor, no reaction to a player action, and no bump
        // reaction, so these read 0.
        for function in [
            unmodelled(247, "GetIsUsedItemType", .integer), unmodelled(305, "GetPlayerAction"),
            unmodelled(274, "IsSmallBump"), unmodelled(642, "GetLastBumpDirection")
        ] {
            registry.register(function)
        }
    }

    /// The keyword parameter matched by editor ID against the attack in progress.
    private static func installAttackType(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 697, name: "IsAttackType", parameter1: .formID
        ) { call in
            guard
                let store = call.context.data.keywords,
                let plugin = call.context.data.sourcePlugin,
                let parameter = call.parameter1,
                let keyword = store.resolve(parameter.asFormID, fromPlugin: plugin)
            else { return .failure(.unavailableData(.keyword)) }
            return Self.action(call) { action in
                Self.isTrue(action.attackTypeKeyword == keyword.keyword.editorID)
            }
        })
    }

    private static func unmodelled(
        _ index: UInt16, _ name: String, _ parameter: ConditionParameterType = .unused
    ) -> ConditionFunction {
        ConditionFunction(index: index, name: name, parameter1: parameter) { call in
            call.actorState().map { _ in 0 }
        }
    }
}
