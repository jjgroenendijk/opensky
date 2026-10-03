// Actor-body condition functions, from xEdit wbDefinitionsTES5.pas: 102
// IsTorchOut, 103 IsShieldOut, 365 IsChild. Vanilla idle markers test them, so
// an idle stays blocked until they answer. See docs/engine/condition-functions.md.

import Foundation
import OpenSkyConditions

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
