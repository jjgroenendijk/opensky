// The combat state as conditions read it (`ActorActionFacts`): the player's melee
// graph state, and each NPC's behaviour phase. See docs/engine/condition-functions.md.

import Foundation
import OpenSkyActorsInterface

nonisolated extension MeleeCombatState {
    public var actionFacts: ActorActionFacts {
        ActorActionFacts(
            attackState: attackPhase.attackState,
            isBlocking: isBlocking,
            isStaggered: isStaggering
        )
    }
}

nonisolated extension MeleeAttackPhase {
    /// Wind-up is the draw of the swing, and recovery its follow-through.
    public var attackState: ActorAttackState {
        switch self {
        case .idle: .none
        case .windup: .draw
        case .swinging: .swing
        case .contact: .hit
        case .recovery: .followThrough
        }
    }
}

nonisolated extension CombatBehaviorPhase {
    /// A blocking NPC both wants to block and has its guard up.
    public var actionFacts: ActorActionFacts {
        let attack: ActorAttackState = switch self {
        case .windup: .draw
        case .contact: .hit
        case .recovery: .followThrough
        default: .none
        }
        return ActorActionFacts(
            attackState: attack,
            isBlocking: self == .blocking,
            isStaggered: self == .staggered,
            isFleeing: self == .fleeing
        )
    }
}
