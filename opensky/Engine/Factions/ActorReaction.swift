// How one actor regards another before anything is decided about drawing a
// weapon (issue #503, roadmap item 21.3).
//
// Four values, because that is how many the Creation Kit authors: a FACT
// interfaction relation carries one of them directly (`Faction.CombatReaction`)
// and a RELA relationship rank collapses onto them in groups the Creation Kit
// wiki spells out. Keeping one enum for both is what lets the derivation write
// "the most hostile reaction wins" once instead of twice.
//
// References:
//   Creation Kit wiki "Faction", Interfaction Relations:
//   "Enemy: Enemy actors are attacked on sight by Aggressive, Very Aggressive,
//   and Frenzied actors, and are not assisted by anyone. Neutral: This is how
//   all factions relate to each other by default [...] Neutrals will be attacked
//   by Very Aggressive and Frenzied actors. Friend: Friends will only be
//   attacked by Frenzied actors, and will be assisted by Helps Friends and
//   Allies actors. Ally: Allies will only be attacked by Frenzied actors, and
//   will be assisted by Helps Friends and Allies and Helps Allies actors."
//   <https://ck.uesp.net/wiki/Faction>
//   Creation Kit wiki "Relationship", which groups the nine ranks under those
//   same four headings and states "relationships override factions":
//   <https://ck.uesp.net/wiki/Relationship>
//
// Documented in docs/engine/combat.md.

import Foundation

/// One actor's regard for another, friendliest first.
///
/// `Comparable` on purpose, and the order is the point: `max` of two reactions
/// is the more hostile one, which is the rule the derivation applies when an
/// actor's several factions disagree about the same target.
nonisolated enum ActorReaction: UInt8, Comparable, CaseIterable, Sendable {
    case ally = 0
    case friend = 1
    case neutral = 2
    case enemy = 3

    /// The reaction a FACT interfaction relation declares, or nil for a raw
    /// value outside the four the spec names — a mod may author one, and
    /// reading it as any of these would be an invention.
    init?(_ reaction: Faction.CombatReaction) {
        switch reaction {
        case .ally: self = .ally
        case .friend: self = .friend
        case .neutral: self = .neutral
        case .enemy: self = .enemy
        case .unknown: return nil
        }
    }

    /// The reaction a RELA rank collapses onto, per the Creation Kit wiki's own
    /// grouping of the nine ranks under the four relation headings, or nil for
    /// a rank the spec does not name.
    ///
    /// Note where the line falls: `rival` and `foe` are grouped under
    /// **Neutral**, not under Enemy. Two actors who dislike each other do not
    /// attack each other on sight unless one of them is Very Aggressive, which
    /// is the same treatment strangers get.
    init?(_ rank: RelationshipRank) {
        switch rank {
        case .lover, .ally: self = .ally
        case .confidant, .friend: self = .friend
        case .acquaintance, .rival, .foe: self = .neutral
        case .enemy, .archnemesis: self = .enemy
        case .unknown: return nil
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .ally: "ally"
        case .friend: "friend"
        case .neutral: "neutral"
        case .enemy: "enemy"
        }
    }

    /// Whether an actor with this aggression attacks somebody it regards this
    /// way, without any provocation.
    ///
    /// Straight from the two Creation Kit tables quoted at the top of this
    /// file, read in the aggression direction: Unaggressive "will not initiate
    /// combat", Aggressive "will attack Enemies on sight", Very Aggressive
    /// "will attack Enemies and Neutrals on sight", Frenzied "will attack
    /// anyone on sight" (<https://ck.uesp.net/wiki/AI_Data_Tab>).
    ///
    /// An aggression value the spec does not name does not attack. The engine
    /// refuses to guess what a mod's fifth aggression level meant, and refusing
    /// upward — into a drawn weapon — would be the damaging direction to guess.
    func provokesAttack(at aggression: ActorAggression) -> Bool {
        switch aggression {
        case .unaggressive: false
        case .aggressive: self == .enemy
        case .veryAggressive: self == .enemy || self == .neutral
        case .frenzied: true
        case .unknown: false
        }
    }
}
