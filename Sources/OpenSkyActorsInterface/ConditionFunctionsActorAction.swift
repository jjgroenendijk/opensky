// Combat-action condition functions, indices from xEdit wbDefinitionsTES5.pas: 0
// GetWantBlocking, 101 IsWeaponMagicOut, 329 IsFleeing, 569 IsBlocking, 574
// GetAttackState, 672 IsAttacking, 673 IsPowerAttacking, 701 IsStaggered, 702
// IsRecoiling, 725 GetKnockedStateEnum, 513 IsCombatTarget, 707
// GetCombatTargetHasKeyword. See
// docs/engine/condition-functions-world.md#combat-actions.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

nonisolated extension ConditionFunctions {
    public static func installActorAction(_ registry: inout ConditionFunctionRegistry) {
        let flags: [String: (index: UInt16, read: @Sendable (ActorActionFacts) -> Bool)] = [
            "GetWantBlocking": (0, { $0.wantsBlocking }),
            "IsFleeing": (329, { $0.isFleeing }),
            "IsBlocking": (569, { $0.isBlocking }),
            "IsAttacking": (672, { $0.attackState.isAttacking }),
            "IsPowerAttacking": (673, { $0.isPowerAttacking }),
            "IsStaggered": (701, { $0.isStaggered }),
            "IsRecoiling": (702, { $0.isRecoiling })
        ]
        for (name, (index, read)) in flags.sorted(by: { $0.key < $1.key }) {
            registry.register(ConditionFunction(index: index, name: name) { call in
                Self.action(call) { Self.isTrue(read($0)) }
            })
        }
        registry.register(ConditionFunction(index: 574, name: "GetAttackState") { call in
            Self.action(call) { Float($0.attackState.rawValue) }
        })
        // 0 is the normal, standing state. OpenSky knocks no living actor down.
        registry.register(ConditionFunction(index: 725, name: "GetKnockedStateEnum") { call in
            Self.action(call) { _ in 0 }
        })
        // A weapon or a spell in hand: the draw state covers both.
        registry.register(ConditionFunction(index: 101, name: "IsWeaponMagicOut") { call in
            call.actorState().flatMap { state in
                guard let drawState = state.weaponDrawState else {
                    return .failure(.unavailableActorState)
                }
                return .success(Self.isTrue(drawState.isWeaponInHand))
            }
        })
        installCombatTarget(&registry)
    }

    private static func installCombatTarget(_ registry: inout ConditionFunctionRegistry) {
        // The parameter actor is the one the run-on fights.
        registry.register(ConditionFunction(
            index: 513, name: "IsCombatTarget", parameter1: .formID
        ) { call in
            guard let other = Self.parameterKey(call, call.parameter1) else {
                return .failure(.unresolvedParameter(513))
            }
            return call.actorState().map { Self.isTrue($0.combatTarget == other) }
        })
        // The target's base `KWDA` or its race's keywords, as `HasKeyword` on an actor.
        registry.register(ConditionFunction(
            index: 707, name: "GetCombatTargetHasKeyword", parameter1: .formID
        ) { call in
            guard
                let store = call.context.data.keywords,
                let plugin = call.context.data.sourcePlugin,
                let keyword = call.parameter1.flatMap({ store.resolvedID(
                    $0.asFormID,
                    fromPlugin: plugin
                ) })
            else { return .failure(.unavailableData(.keyword)) }
            return call.actorState().flatMap { state in
                guard let target = state.combatTarget else { return .success(0) }
                let race = call.context.actors.state(for: target)?.raceKeywords ?? []
                if race.contains(where: { store.resolvedID($0, fromPlugin: plugin) == keyword }) {
                    return .success(1)
                }
                guard let entry = call.context.references[target] else { return .success(0) }
                let base = store.resolvedID(
                    Self.baseForm(of: entry), fromPlugin: Self.basePlugin(of: entry.key)
                )
                return .success(Self
                    .isTrue(base.flatMap { store.hasKeyword(keyword, on: $0) } == true))
            }
        })
    }

    /// One read of the run-on actor's action facts; unobserved is `.unavailableActorState`.
    static func action(
        _ call: ConditionCall,
        read: (ActorActionFacts) -> Float
    ) -> Result<Float, ConditionFailure> {
        call.actorState().flatMap { state in
            guard let action = state.action else { return .failure(.unavailableActorState) }
            return .success(read(action))
        }
    }
}
