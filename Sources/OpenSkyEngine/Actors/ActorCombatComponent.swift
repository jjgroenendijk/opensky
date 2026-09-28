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
nonisolated public enum ActorHostility: UInt8, Equatable, Sendable, CaseIterable {
    /// The actor has no quarrel with the player. Every actor starts here.
    case neutral = 0
    /// The actor fights the player: the dev-target driver attacks from this
    /// state, and it is what `IsInCombat` and `GetCombatState` read.
    case hostile = 1

    public var displayName: String {
        switch self {
        case .neutral: "neutral"
        case .hostile: "hostile"
        }
    }
}

/// One actor's hostility toward the player.
nonisolated public struct ActorCombatState: WorldStateComponent, Equatable, Sendable {
    public var hostility: ActorHostility

    public static let hostile = ActorCombatState(hostility: .hostile)
    public static let neutral = ActorCombatState(hostility: .neutral)

    public static var componentKind: WorldStateComponentKind {
        .combat
    }

    public init(hostility: ActorHostility) {
        self.hostility = hostility
    }
}

nonisolated extension WorldStateComponentKind {
    /// One actor's hostility toward the player. A slot of its own beside
    /// `actorValues` and `death` for the same lifetime reason those two are
    /// separate: hostility changes on a handful of events, while the values beside
    /// it are rewritten sixty times a second.
    public static let combat = Self(rawValue: "combat", order: 10)
}

nonisolated extension WorldStateComponentValue {
    public static func combat(_ value: ActorCombatState) -> Self {
        Self(value)
    }
}
