// The combat state as conditions read it (`ActorActionFacts`): the player's melee
// graph state, strike, and bow shot, and each NPC's behaviour phase.
// See docs/engine/condition-functions.md.

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

extension MeleeCombatRuntime {
    /// The graph state plus the strike in progress, which `IsPowerAttacking` and
    /// `IsAttackType` read.
    public var actionFacts: ActorActionFacts {
        var facts = state.actionFacts
        guard state.attackPhase != .idle else { return facts }
        if strikeKind.isBash {
            facts.attackState = .bash
        }
        facts.isPowerAttacking = strikeKind.isPowerAttack
        facts.attackTypeKeyword = switch strikeKind {
        case .power: powerDirection?.attackTypeKeyword
        case .powerBash: "PowerAttackBash"
        case .normal, .bash: nil
        }
        return facts
    }
}

nonisolated extension MeleePowerDirection {
    /// The vanilla attack-type keyword of a power attack this way. A sideways
    /// attack is one keyword for both sides.
    public var attackTypeKeyword: String {
        switch self {
        case .inPlace: "PowerAttackTypeStanding"
        case .forward: "PowerAttackTypeForward"
        case .backward: "PowerAttackTypeBack"
        case .left, .right: "PowerAttackTypeSide"
        }
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

nonisolated extension ArcheryShotPhase {
    /// The wiki has no nock code, so nocking counts as drawing.
    public var attackState: ActorAttackState {
        switch self {
        case .idle: .none
        case .nocked, .drawing: .drawingBow
        case .drawn: .holdingBowDrawn
        case .loosed: .loosingArrow
        }
    }
}

extension CombatCoordinator {
    /// A shot in progress decides the attack state; otherwise the melee graph does.
    public var playerActionFacts: ActorActionFacts? {
        guard var facts = melee?.actionFacts else { return nil }
        if let phase = archery?.state.phase, phase != .idle {
            facts.attackState = phase.attackState
        }
        return facts
    }
}
