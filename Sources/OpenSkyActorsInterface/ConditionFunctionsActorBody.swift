// Actor-body condition functions, from xEdit wbDefinitionsTES5.pas: 69 GetIsRace,
// 102 IsTorchOut, 103 IsShieldOut, 313 GetPairedAnimation, 365 IsChild, 594
// GetIsFlying. Idle markers and camera paths test them.
// See docs/engine/condition-functions.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

nonisolated extension ConditionFunctions {
    public static func installActorBody(_ registry: inout ConditionFunctionRegistry) {
        // 1 when the actor holds a torch out.
        registry.register(ConditionFunction(index: 102, name: "IsTorchOut") { call in
            Self.leftHand(call) { $0 == .torch }
        })

        // 1 when the actor holds a shield out with its weapon.
        registry.register(ConditionFunction(index: 103, name: "IsShieldOut") { call in
            Self.leftHand(call) { $0 == .shield }
        })

        // 1 when the actor's race has the `DATA` child flag (xEdit 0x04).
        registry.register(ConditionFunction(index: 365, name: "IsChild") { call in
            call.actorState().map { Self.isTrue($0.isChild) }
        })

        registry.register(ConditionFunction(
            index: 69, name: "GetIsRace", parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(69))
            }
            return call.actorState().flatMap { state in
                guard let race = state.race else { return .failure(.unavailableActorState) }
                return .success(Self.isTrue(race == parameter.asFormID))
            }
        })

        // 1 while the actor plays a paired animation, such as a kill move.
        registry.register(ConditionFunction(index: 313, name: "GetPairedAnimation") { call in
            call.actorState().map { Self.isTrue($0.isInPairedAnimation) }
        })

        registry.register(ConditionFunction(index: 594, name: "GetIsFlying") { call in
            call.actorState().map { Self.isTrue($0.isFlying) }
        })
    }

    /// An unobserved left hand is `.unavailableActorState`, not 0.
    private static func leftHand(
        _ call: ConditionCall,
        _ test: (ActorLeftHandOut) -> Bool
    ) -> Result<Float, ConditionFailure> {
        call.actorState().flatMap { state in
            guard let hand = state.leftHandOut else { return .failure(.unavailableActorState) }
            return .success(Self.isTrue(test(hand)))
        }
    }
}
