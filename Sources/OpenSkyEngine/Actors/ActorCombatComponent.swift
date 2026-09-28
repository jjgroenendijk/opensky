// Persistent hostility (issue #374, roadmap item 15.7): the world-state
// component that makes an actor still angry after a save and a reload.
//
// It sits beside `ActorValueState` and `ActorDeathState` rather than inside
// either, for the reason the death latch sits beside the values: the three have
// different lifetimes. Current health is rewritten by every regeneration step,
// death is a one-way latch, and hostility is a small state that changes rarely
// and is cleared by nothing but a panel toggle or a resurrection.
//
// ## What hostility is, and what it deliberately is not
//
// It is one enum per actor, entered when the player damages that actor or when
// the panel toggle sets it. There is no aggro radius, no faction relation, no
// disposition arithmetic and no crime: those need perception and packages, and
// both are M16's. An actor is neutral until something the player did made it
// hostile, and it stays that way until told otherwise.
//
// The *player's* combat state is not stored here at all. "Am I in combat" is a
// derived question — is any resident actor hostile and alive — and deriving it
// keeps it from going stale against a corpse or an evicted cell. See
// `CombatLoopState`.
//
// Documented in docs/engine/combat.md.

import Foundation

/// How one actor regards the player.
///
/// Two cases rather than three: "dead" is `ActorDeathState.isDead` and would be
/// a second, disagreeing record of the same fact if it were also spelled here.
nonisolated enum ActorHostility: UInt8, Equatable, Sendable, CaseIterable {
    /// The actor has no quarrel with the player. Every actor starts here.
    case neutral = 0
    /// The actor fights the player: the dev-target driver attacks from this
    /// state, and it is what `IsInCombat` and `GetCombatState` read.
    case hostile = 1

    var displayName: String {
        switch self {
        case .neutral: "neutral"
        case .hostile: "hostile"
        }
    }
}

/// One actor's hostility toward the player.
nonisolated struct ActorCombatState: WorldStateComponent, Equatable {
    var hostility: ActorHostility

    static let hostile = ActorCombatState(hostility: .hostile)
    static let neutral = ActorCombatState(hostility: .neutral)

    static var componentKind: WorldStateComponentKind {
        .combat
    }

    var erased: WorldStateComponentValue {
        .combat(self)
    }

    init(hostility: ActorHostility) {
        self.hostility = hostility
    }

    init?(erased: WorldStateComponentValue) {
        guard case let .combat(value) = erased else { return nil }
        self = value
    }
}
