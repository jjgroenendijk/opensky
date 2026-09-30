// Persistent hostility: the component that keeps an actor angry after a reload.
// It is separate from values and death, because the lifetimes differ. An actor
// turns hostile when the player damages it or the panel sets it. The player's
// own combat state is derived, not stored (`CombatLoopState`).
// See docs/engine/combat.md.

import Foundation
import OpenSkyWorldState

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
