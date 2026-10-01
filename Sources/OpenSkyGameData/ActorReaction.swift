// How one actor regards another: Enemy, Neutral, Friend or Ally. A FACT relation
// names one (<https://ck.uesp.net/wiki/Faction>); a RELA rank maps onto them
// (<https://ck.uesp.net/wiki/Relationship>). One enum, so "most hostile wins" is
// written once. See docs/engine/hostility.md.

import Foundation
import OpenSkyFormatsESM

/// One actor's regard for another, friendliest first.
///
/// `Comparable` on purpose, and the order is the point: `max` of two reactions
/// is the more hostile one, which is the rule the derivation applies when an
/// actor's several factions disagree about the same target.
nonisolated public enum ActorReaction: UInt8, Comparable, CaseIterable, Sendable {
    case ally = 0
    case friend = 1
    case neutral = 2
    case enemy = 3

    /// The reaction a FACT interfaction relation declares, or nil for a raw
    /// value outside the four the spec names — a mod may author one, and
    /// reading it as any of these would be an invention.
    public init?(_ reaction: Faction.CombatReaction) {
        switch reaction {
        case .ally: self = .ally
        case .friend: self = .friend
        case .neutral: self = .neutral
        case .enemy: self = .enemy
        case .unknown: return nil
        }
    }

    /// The reaction a RELA rank maps onto, per the wiki's grouping, or nil for an
    /// unnamed rank. `rival` and `foe` are Neutral, not Enemy.
    public init?(_ rank: RelationshipRank) {
        switch rank {
        case .lover, .ally: self = .ally
        case .confidant, .friend: self = .friend
        case .acquaintance, .rival, .foe: self = .neutral
        case .enemy, .archnemesis: self = .enemy
        case .unknown: return nil
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .ally: "ally"
        case .friend: "friend"
        case .neutral: "neutral"
        case .enemy: "enemy"
        }
    }

    /// Whether this aggression attacks an actor regarded this way unprovoked
    /// (<https://ck.uesp.net/wiki/AI_Data_Tab>). An unnamed aggression value does not
    /// attack, because guessing toward a drawn weapon is the harmful direction.
    public func provokesAttack(at aggression: ActorAggression) -> Bool {
        switch aggression {
        case .unaggressive: false
        case .aggressive: self == .enemy
        case .veryAggressive: self == .enemy || self == .neutral
        case .frenzied: true
        case .unknown: false
        }
    }
}
