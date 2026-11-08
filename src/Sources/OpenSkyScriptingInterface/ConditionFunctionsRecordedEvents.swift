// Condition functions over what the engine recorded on a form as it happened: 408
// `IsKiller`, 203 `GetDestroyed`, 470 `GetDestructionStage`, 288 `GetFriendHit`, and
// 674 `IsLastHostileActor`, indices from xEdit wbDefinitionsTES5.pas.
// See docs/engine/condition-functions-world.md#recorded-events.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

nonisolated extension ConditionFunctions {
    static func installRecordedEvents(_ registry: inout ConditionFunctionRegistry) {
        // `ptActor`: true when the run-on killed the parameter actor.
        registry.register(ConditionFunction(
            index: 408, name: "IsKiller", parameter1: .formID
        ) { call in
            guard let victim = Self.parameterKey(call, call.parameter1) else {
                return .failure(.unresolvedParameter(408))
            }
            return call.referenceKey().flatMap { key in
                Self.scriptState(call, of: victim).map {
                    Self.isTrue($0.form(ScriptedStateName.killer) == key)
                }
            }
        })
        registry.register(ConditionFunction(index: 203, name: "GetDestroyed") { call in
            Self.recorded(call) { Self.isTrue($0.flag(ScriptedStateName.destroyed) == true) }
        })
        registry.register(ConditionFunction(index: 470, name: "GetDestructionStage") { call in
            Self.recorded(call) { $0.value(ScriptedStateName.destructionStage) ?? 0 }
        })
        registry.register(ConditionFunction(index: 288, name: "GetFriendHit") { call in
            Self.recorded(call) { $0.value(ScriptedStateName.friendHits) ?? 0 }
        })
        registry.register(ConditionFunction(index: 674, name: "IsLastHostileActor") { call in
            call.referenceKey().flatMap { key in
                Self.scriptState(call, of: .player).map {
                    Self.isTrue($0.form(ScriptedStateName.lastHostileActor) == key)
                }
            }
        })
    }

    private static func recorded(
        _ call: ConditionCall, read: (ScriptedReferenceState) -> Float
    ) -> Result<Float, ConditionFailure> {
        call.referenceKey().flatMap { key in Self.scriptState(call, of: key).map(read) }
    }
}
