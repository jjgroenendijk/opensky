// How the hostility derivation merges faction relations when memberships disagree.

@testable import OpenSkyActorsInterface
@testable import OpenSkyFactions
import OpenSkyFactionsFixtures
@testable import OpenSkyFactionsInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct HostilityFactionMergeTests {
    private typealias Fixture = HostilityFixture

    /// Several memberships disagreeing: the friendliest pair that is not Neutral wins,
    /// as at Helgen, where a shared temporary Friend faction keeps two enemy sides calm.
    @Test
    func aFriendPairBeatsAnEnemyPair() throws {
        let derivation = try Fixture.derivation(relations: [
            Fixture.Relation(Fixture.Factions.bandit, Fixture.Factions.guards, .enemy),
            Fixture.Relation(Fixture.Factions.guards, Fixture.Factions.bandit, .enemy),
            Fixture.Relation(Fixture.Factions.town, Fixture.Factions.town, .friend)
        ])
        let bandit = Fixture.profile(
            actor: Fixture.Actors.bandit,
            memberships: [(Fixture.Factions.bandit, 0), (Fixture.Factions.town, 0)]
        )
        let cityGuard = Fixture.profile(
            actor: Fixture.Actors.cityGuard,
            memberships: [(Fixture.Factions.guards, 0), (Fixture.Factions.town, 0)]
        )
        #expect(derivation.decide(bandit, toward: cityGuard).reaction == .friend)
        #expect(derivation.decide(cityGuard, toward: bandit).reaction == .friend)
        #expect(derivation.decide(cityGuard, toward: bandit).source == .faction)
    }

    /// A membership at rank -1 takes no part in the merge.
    @Test
    func aMembershipAtRankMinusOneIsSkipped() throws {
        let derivation = try Fixture.derivation(relations: [
            Fixture.Relation(Fixture.Factions.bandit, Fixture.Factions.guards, .enemy),
            Fixture.Relation(Fixture.Factions.town, Fixture.Factions.guards, .ally)
        ])
        let decision = derivation.decide(
            Fixture.profile(
                actor: Fixture.Actors.bandit,
                memberships: [(Fixture.Factions.town, -1), (Fixture.Factions.bandit, 2)]
            ),
            toward: Fixture.profile(
                actor: Fixture.Actors.cityGuard,
                memberships: [(Fixture.Factions.guards, 0)]
            )
        )
        #expect(decision.reaction == .enemy)
        #expect(decision.source == .faction)
    }

    /// Only the observer's factions' relations count; the target's relations back do not.
    @Test
    func onlyTheObserversRelationsCount() throws {
        let derivation = try Fixture.derivation(relations: [
            Fixture.Relation(Fixture.Factions.guards, Fixture.Factions.bandit, .enemy)
        ])
        let bandit = Fixture.profile(
            actor: Fixture.Actors.bandit, memberships: [(Fixture.Factions.bandit, 0)]
        )
        let cityGuard = Fixture.profile(
            actor: Fixture.Actors.cityGuard, memberships: [(Fixture.Factions.guards, 0)]
        )
        #expect(derivation.decide(bandit, toward: cityGuard).reaction == .neutral)
        #expect(derivation.decide(cityGuard, toward: bandit).reaction == .enemy)
        #expect(derivation.decide(cityGuard, toward: bandit).source == .faction)
    }
}
