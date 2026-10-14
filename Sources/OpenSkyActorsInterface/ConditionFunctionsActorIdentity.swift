// Actor identity and activity condition functions, from xEdit wbDefinitionsTES5.pas:
// 70 GetIsSex, 130 GetPCIsRace, 131 GetPCIsSex, 286 IsSneaking, 289 IsInCombat,
// 430 GetHealthPercentage. Dialogue tests them most.
// See docs/engine/condition-functions.md#actors.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension ConditionFunctions {
    public static func installActorIdentity(_ registry: inout ConditionFunctionRegistry) {
        // xEdit `ptSex`: 0 male, 1 female (<https://ck.uesp.net/wiki/GetIsSex>).
        registry.register(ConditionFunction(
            index: 70, name: "GetIsSex", parameter1: .integer
        ) { call in
            call.actorState().flatMap { Self.isSex($0, call.parameter1, index: 70) }
        })

        // GetIsSex for the player, whatever the run-on.
        registry.register(ConditionFunction(
            index: 131, name: "GetPCIsSex", parameter1: .integer
        ) { call in
            Self.playerState(call).flatMap { Self.isSex($0, call.parameter1, index: 131) }
        })

        // "Same as GetIsRace, but only applies to the player."
        // (<https://ck.uesp.net/wiki/GetPCIsRace>)
        registry.register(ConditionFunction(
            index: 130, name: "GetPCIsRace", parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(130))
            }
            return Self.playerState(call).flatMap { state in
                guard let race = state.race else { return .failure(.unavailableActorState) }
                return .success(Self.isTrue(race == parameter.asFormID))
            }
        })

        // "Returns 1 if the actor is currently in combat." Searching is still combat,
        // as `GetCombatState` 2 is (<https://ck.uesp.net/wiki/IsInCombat>).
        registry.register(ConditionFunction(index: 289, name: "IsInCombat") { call in
            call.actorState().map { Self.isTrue($0.combatStateValue != 0) }
        })

        // Health over its maximum, 0 to 1; vanilla compares it with 0.25 to 1.
        registry.register(ConditionFunction(index: 430, name: "GetHealthPercentage") { call in
            call.actorState().flatMap { state in
                guard let fraction = state.fraction(at: ActorValueIdentity.index(of: .health))
                else { return .failure(.unavailableActorState) }
                return .success(fraction)
            }
        })

        registry.register(ConditionFunction(index: 286, name: "IsSneaking") { call in
            call.actorState().flatMap { state in
                guard let sneaking = state.isSneaking else {
                    return .failure(.unavailableActorState)
                }
                return .success(Self.isTrue(sneaking))
            }
        })
    }

    private static func isSex(
        _ state: ActorConditionState,
        _ parameter: Condition.Parameter?,
        index: UInt16
    ) -> Result<Float, ConditionFailure> {
        guard let parameter, (0 ... 1).contains(parameter.asInt32) else {
            return .failure(.unresolvedParameter(index))
        }
        guard let isFemale = state.isFemale else { return .failure(.unavailableActorState) }
        return .success(Self.isTrue(isFemale == (parameter.asInt32 == 1)))
    }

    private static func playerState(
        _ call: ConditionCall
    ) -> Result<ActorConditionState, ConditionFailure> {
        guard let state = call.context.actors.state(for: .player) else {
            return .failure(.unavailableActorState)
        }
        return .success(state)
    }
}
