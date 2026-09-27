// The hostility derivation (issue #503, roadmap item 21.3): the reaction matrix
// across the four interfaction relations, a RELA record overriding faction
// neutrality, the crime seam, and the precedence order the whole thing is
// documented by. No game-derived bytes.

import Foundation
@testable import opensky
import Testing

struct HostilityDerivationTests {
    private typealias Fixture = HostilityFixture

    /// Each of the four relations, read through an Aggressive actor — the
    /// vanilla guard setting, which attacks enemies and nobody else.
    @Test
    func derivesEveryRelationFromTheFactionsTwoActorsBelongTo() throws {
        let matrix: [(Faction.CombatReaction, ActorReaction)] = [
            (.enemy, .enemy),
            (.neutral, .neutral),
            (.friend, .friend),
            (.ally, .ally)
        ]
        for (authored, expected) in matrix {
            let derivation = try Fixture.derivation(relations: [
                Fixture.Relation(Fixture.Factions.bandit, Fixture.Factions.guards, authored)
            ])
            let decision = derivation.decide(
                Fixture.profile(
                    actor: Fixture.Actors.bandit,
                    memberships: [(Fixture.Factions.bandit, 0)]
                ),
                toward: Fixture.profile(
                    actor: Fixture.Actors.cityGuard,
                    memberships: [(Fixture.Factions.guards, 0)]
                )
            )
            #expect(decision.reaction == expected, "\(authored)")
            // Aggressive: attacks enemies on sight, and nobody else.
            #expect(decision.isHostile == (expected == .enemy), "\(authored)")
            #expect(decision.source == .faction, "\(authored)")
        }
    }

    /// Nobody authored anything about the pair: the Creation Kit's documented
    /// default, and the case a bandit and the player actually fall into.
    @Test
    func twoStrangersAreNeutralAndOnlyAVeryAggressiveActorAttacksThem() throws {
        let derivation = try Fixture.derivation()
        let player = Fixture.player()

        for aggression in [ActorAggression.unaggressive, .aggressive] {
            let calm = derivation.decide(
                Fixture.profile(
                    actor: Fixture.Actors.bandit,
                    memberships: [(Fixture.Factions.bandit, 0)],
                    aggression: aggression
                ),
                toward: player
            )
            #expect(calm.reaction == .neutral)
            #expect(calm.source == .defaultNeutral)
            #expect(!calm.isHostile, "\(aggression)")
        }

        let bandit = derivation.decide(
            Fixture.profile(
                actor: Fixture.Actors.bandit,
                memberships: [(Fixture.Factions.bandit, 0)],
                aggression: .veryAggressive
            ),
            toward: player
        )
        #expect(bandit.isHostile)
        #expect(bandit.reaction == .neutral)
        #expect(bandit.source == .defaultNeutral)
    }

    /// "Relationships override factions" (Creation Kit wiki), in both
    /// directions: a RELA can make two friendly-faction actors enemies and two
    /// enemy-faction actors allies.
    @Test
    func aRelationshipOverridesWhateverTheFactionsSay() throws {
        let friendly = try Fixture.derivation(
            relations: [
                Fixture.Relation(Fixture.Factions.town, Fixture.Factions.guards, .friend)
            ],
            pairs: [Fixture.Pair(Fixture.Actors.townsfolk, Fixture.Actors.cityGuard, .archnemesis)]
        )
        let feud = friendly.decide(
            Fixture.profile(
                actor: Fixture.Actors.townsfolk,
                memberships: [(Fixture.Factions.town, 0)]
            ),
            toward: Fixture.profile(
                actor: Fixture.Actors.cityGuard,
                memberships: [(Fixture.Factions.guards, 0)]
            )
        )
        #expect(feud.reaction == .enemy)
        #expect(feud.source == .relationship)
        #expect(feud.isHostile)

        let hostileFactions = try Fixture.derivation(
            relations: [
                Fixture.Relation(Fixture.Factions.bandit, Fixture.Factions.guards, .enemy)
            ],
            pairs: [Fixture.Pair(Fixture.Actors.bandit, Fixture.Actors.cityGuard, .lover)]
        )
        let truce = hostileFactions.decide(
            Fixture.profile(
                actor: Fixture.Actors.bandit,
                memberships: [(Fixture.Factions.bandit, 0)]
            ),
            toward: Fixture.profile(
                actor: Fixture.Actors.cityGuard,
                memberships: [(Fixture.Factions.guards, 0)]
            )
        )
        #expect(truce.reaction == .ally)
        #expect(truce.source == .relationship)
        #expect(!truce.isHostile)
    }

    /// The pair index is order-free, so the override works whichever side the
    /// record called the parent.
    @Test
    func theRelationshipIsFoundFromEitherSide() throws {
        let derivation = try Fixture.derivation(
            pairs: [Fixture.Pair(Fixture.Actors.cityGuard, Fixture.Actors.bandit, .enemy)]
        )
        let bandit = Fixture.profile(actor: Fixture.Actors.bandit)
        let guards = Fixture.profile(actor: Fixture.Actors.cityGuard)

        #expect(derivation.reaction(of: bandit, toward: guards) == .enemy)
        #expect(derivation.reaction(of: guards, toward: bandit) == .enemy)
    }

    /// A RELA names two NPC_ bases, and the player has none, so the term simply
    /// does not apply to the player.
    @Test
    func aPlayerWithNoBaseRecordNeverMatchesARelationship() throws {
        let derivation = try Fixture.derivation(
            pairs: [Fixture.Pair(Fixture.Actors.bandit, Fixture.Actors.cityGuard, .enemy)]
        )
        let decision = derivation.decide(
            Fixture.profile(actor: Fixture.Actors.bandit),
            toward: Fixture.player()
        )
        #expect(decision.source == .defaultNeutral)
        #expect(decision.reaction == .neutral)
    }

    /// Several memberships disagreeing: the most hostile of them wins, which is
    /// this engine's rule rather than a documented one.
    @Test
    func theMostHostileMembershipPairWins() throws {
        let derivation = try Fixture.derivation(relations: [
            Fixture.Relation(Fixture.Factions.town, Fixture.Factions.guards, .ally),
            Fixture.Relation(Fixture.Factions.bandit, Fixture.Factions.guards, .enemy)
        ])
        let decision = derivation.decide(
            Fixture.profile(
                actor: Fixture.Actors.bandit,
                memberships: [(Fixture.Factions.town, 0), (Fixture.Factions.bandit, 2)]
            ),
            toward: Fixture.profile(
                actor: Fixture.Actors.cityGuard,
                memberships: [(Fixture.Factions.guards, 0)]
            )
        )
        #expect(decision.reaction == .enemy)
        #expect(decision.source == .faction)
    }

    /// An XNAM authored on one side only is still an opinion about the pair.
    @Test
    func aRelationAuthoredOnEitherSideCounts() throws {
        let derivation = try Fixture.derivation(relations: [
            Fixture.Relation(Fixture.Factions.guards, Fixture.Factions.bandit, .enemy)
        ])
        let decision = derivation.decide(
            Fixture.profile(
                actor: Fixture.Actors.bandit,
                memberships: [(Fixture.Factions.bandit, 0)]
            ),
            toward: Fixture.profile(
                actor: Fixture.Actors.cityGuard,
                memberships: [(Fixture.Factions.guards, 0)]
            )
        )
        #expect(decision.reaction == .enemy)
        #expect(decision.source == .faction)
    }

    /// The whole precedence list, walked from the bottom up: each term added in
    /// turn takes the answer away from the one below it.
    @Test
    func theOverrideBeatsCrimeBeatsRelationshipBeatsFaction() throws {
        var derivation = try Fixture.derivation(
            relations: [
                Fixture.Relation(Fixture.Factions.bandit, Fixture.Factions.guards, .enemy)
            ],
            pairs: [Fixture.Pair(Fixture.Actors.bandit, Fixture.Actors.cityGuard, .friend)]
        )
        let observer = Fixture.profile(
            actor: Fixture.Actors.bandit,
            memberships: [(Fixture.Factions.bandit, 0)]
        )
        let target = Fixture.profile(
            actor: Fixture.Actors.cityGuard,
            memberships: [(Fixture.Factions.guards, 0)]
        )

        // Relationship over faction.
        #expect(derivation.decide(observer, toward: target).source == .relationship)
        #expect(derivation.decide(observer, toward: target).reaction == .friend)

        // Crime over relationship.
        derivation.crime = FixedCrime(reaction: .enemy)
        let withCrime = derivation.decide(observer, toward: target)
        #expect(withCrime.source == .crime)
        #expect(withCrime.reaction == .enemy)
        #expect(withCrime.isHostile)

        // Override over everything, in both directions.
        let calmed = Fixture.profile(
            actor: Fixture.Actors.bandit,
            memberships: [(Fixture.Factions.bandit, 0)],
            hostilityOverride: .neutral
        )
        let calm = derivation.decide(calmed, toward: target)
        #expect(calm.source == .runtimeOverride)
        #expect(!calm.isHostile)
        // The records are still reported, so a panel can show why the override
        // is disagreeing with them.
        #expect(calm.reaction == .enemy)

        let angered = Fixture.profile(
            actor: Fixture.Actors.townsfolk,
            hostilityOverride: .hostile
        )
        #expect(derivation.decide(angered, toward: target).isHostile)
    }

    /// The seam issues #504 and #505 join through answers nothing until it is
    /// replaced.
    @Test
    func theDefaultCrimeSourceHasNoOpinion() throws {
        let derivation = try Fixture.derivation()
        let observer = Fixture.profile(actor: Fixture.Actors.bandit)

        #expect(NoCrimeHostility().crimeReaction(
            of: observer, toward: Fixture.player()
        ) == nil)
        #expect(derivation.decide(observer, toward: Fixture.player()).source == .defaultNeutral)
    }

    /// Stand-in bounty term: says the same thing about every pair.
    private struct FixedCrime: CrimeHostilitySource {
        let reaction: ActorReaction

        func crimeReaction(
            of observer: ActorSocialProfile,
            toward target: ActorSocialProfile
        ) -> ActorReaction? {
            reaction
        }
    }
}
