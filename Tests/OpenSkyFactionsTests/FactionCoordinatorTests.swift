// The faction shell over a fake world: hostility falls back to the stored
// override without game data, membership writes seed first, and the
// condition seam covers the player and every resident actor. The derivation
// is tested in `HostilityDerivationTests`.

@testable import OpenSkyActorsInterface
@testable import OpenSkyFactions
@testable import OpenSkyFactionsInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorldState
import Testing

@MainActor
struct FactionCoordinatorTests {
    private typealias Fixture = HostilityFixture

    private final class FakeWorld: FactionWorld {
        var residents: [ReferenceKey] = []

        func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
            if key == .player {
                return .player
            }
            guard residents.contains(key), case let .plugin(_, objectID) = key else { return nil }
            return ActorValueHolder(key: key, subject: .actor(base: FormID(objectID)), cell: nil)
        }

        func residentActorKeys() -> [ReferenceKey] {
            residents
        }

        func placedActorBase(of key: ReferenceKey) -> FormID? {
            guard case let .plugin(_, objectID) = key else { return nil }
            return FormID(objectID)
        }

        func cellLocation(of _: ReferenceKey) -> CellSceneLocation? {
            nil
        }
    }

    private static let bandit = Fixture.key(Fixture.Actors.bandit)

    private static func wired(_ world: FakeWorld) throws -> FactionCoordinator {
        let file = try Fixture.file()
        let coordinator = FactionCoordinator(store: WorldStateStore())
        coordinator.attach(world: world)
        coordinator.wire(
            factions: FactionStore(plugins: [(Fixture.pluginName, file)]),
            relationships: RelationshipStore(plugins: [(Fixture.pluginName, file)]),
            baselines: nil,
            pluginName: Fixture.pluginName
        )
        return coordinator
    }

    @Test func withoutGameDataHostilityIsTheStoredOverride() {
        let world = FakeWorld()
        world.residents = [Self.bandit]
        let coordinator = FactionCoordinator(store: WorldStateStore())
        coordinator.attach(world: world)

        #expect(coordinator.hostility(of: Self.bandit) == .neutral)
        #expect(coordinator.setHostility(.hostile, on: Self.bandit))
        #expect(coordinator.hostility(of: Self.bandit) == .hostile)
        #expect(coordinator.derivedHostilityDecision(of: Self.bandit) == nil)
        #expect(!coordinator.conditionResolution().isAvailable)
    }

    @Test func theDerivationAnswersOnceWired() throws {
        let world = FakeWorld()
        world.residents = [Self.bandit]
        let coordinator = try Self.wired(world)
        coordinator.setHostility(.hostile, on: Self.bandit)

        let decision = try #require(coordinator.derivedHostilityDecision(of: Self.bandit))
        #expect(decision.hostility == .hostile)
        #expect(decision.source == .runtimeOverride)
        #expect(coordinator.derivedHostilityDecision(of: .player) == nil)
    }

    @Test func joinAndLeaveNeedAResidentActor() throws {
        let world = FakeWorld()
        let coordinator = try Self.wired(world)
        let faction = Fixture.key(Fixture.Factions.bandit)
        #expect(!coordinator.join(faction, actor: Self.bandit, rank: 2))

        world.residents = [Self.bandit]
        #expect(coordinator.join(faction, actor: Self.bandit, rank: 2))
        #expect(coordinator.memberships(of: Self.bandit)?.rank(in: faction) == 2)
        #expect(coordinator.leave(faction, actor: Self.bandit))
        #expect(coordinator.memberships(of: Self.bandit)?.isMember(of: faction) == false)
    }

    @Test func theConditionSeamProfilesThePlayerAndEveryResident() throws {
        let world = FakeWorld()
        world.residents = [Self.bandit]
        let resolution = try Self.wired(world).conditionResolution()
        #expect(resolution.profile(of: .player) != nil)
        #expect(resolution.profile(of: Self.bandit)?.key == Self.bandit)
    }

    @Test func aSocialDecisionNeedsBothActorsResident() throws {
        let world = FakeWorld()
        let coordinator = try Self.wired(world)
        #expect(coordinator.socialDecision(of: Self.bandit, toward: .player) == nil)

        world.residents = [Self.bandit]
        let decision = try #require(coordinator.socialDecision(of: Self.bandit, toward: .player))
        #expect(!decision.isHostile)
        #expect(decision.factionReaction == .neutral)
    }
}
