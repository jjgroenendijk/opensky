// The reaction enum (issue #503): the two mappings the Creation Kit wiki
// authors, the ordering the derivation relies on, and the aggression table that
// turns a reaction into a drawn weapon. No game-derived bytes.

import Foundation
@testable import opensky
import Testing

struct ActorReactionTests {
    @Test
    func mapsEveryNamedCombatReactionAndRefusesTheRest() {
        #expect(ActorReaction(Faction.CombatReaction.ally) == .ally)
        #expect(ActorReaction(Faction.CombatReaction.friend) == .friend)
        #expect(ActorReaction(Faction.CombatReaction.neutral) == .neutral)
        #expect(ActorReaction(Faction.CombatReaction.enemy) == .enemy)
        #expect(ActorReaction(Faction.CombatReaction.unknown(raw: 9)) == nil)
    }

    /// The Creation Kit wiki's own grouping of the nine ranks. `rival` and
    /// `foe` land on Neutral, not Enemy, which is the grouping's one surprise.
    @Test
    func collapsesTheNineRelationshipRanksTheWayTheWikiGroupsThem() {
        let expected: [(RelationshipRank, ActorReaction)] = [
            (.lover, .ally),
            (.ally, .ally),
            (.confidant, .friend),
            (.friend, .friend),
            (.acquaintance, .neutral),
            (.rival, .neutral),
            (.foe, .neutral),
            (.enemy, .enemy),
            (.archnemesis, .enemy)
        ]
        for (rank, reaction) in expected {
            #expect(ActorReaction(rank) == reaction, "\(rank)")
        }
        #expect(ActorReaction(RelationshipRank.unknown(raw: 42)) == nil)
    }

    /// Ordering is the derivation's "most hostile wins" rule, so it is pinned.
    @Test
    func ordersFromFriendliestToMostHostile() {
        #expect(ActorReaction.allCases == [.ally, .friend, .neutral, .enemy])
        #expect(ActorReaction.ally < ActorReaction.friend)
        #expect(ActorReaction.friend < ActorReaction.neutral)
        #expect(ActorReaction.neutral < ActorReaction.enemy)
        #expect(max(ActorReaction.ally, .enemy) == .enemy)
    }

    /// The whole Creation Kit aggression table, one row per reaction.
    @Test
    func appliesTheAggressionTableToEveryReaction() {
        let attacked: [(ActorAggression, [ActorReaction])] = [
            (.unaggressive, []),
            (.aggressive, [.enemy]),
            (.veryAggressive, [.neutral, .enemy]),
            (.frenzied, [.ally, .friend, .neutral, .enemy]),
            (.unknown(raw: 7), [])
        ]
        for (aggression, expected) in attacked {
            let actual = ActorReaction.allCases.filter { $0.provokesAttack(at: aggression) }
            #expect(actual == expected, "\(aggression)")
        }
    }
}
