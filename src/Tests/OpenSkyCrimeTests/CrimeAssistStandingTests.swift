// What a helper deciding whether to join a fight learns from the crime state: whom guards
// answer, resisting arrest, and who attacks the player on sight for crimes.
// See docs/engine/combat.md#committed-a-crime.

@testable import OpenSkyCrime
import OpenSkyCrimeFixtures
@testable import OpenSkyCrimeInterface
@testable import OpenSkyFactionsInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorldState
import Testing

@MainActor
struct CrimeAssistStandingTests {
    private static let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
    private static let owner = CrimeFixture.key(CrimeFixture.Actors.resident)
    private static let guardKey = CrimeFixture.key(CrimeFixture.Actors.shopkeeper)
    private static let stranger = ReferenceKey.generated(40)
    private static let ring = FormID(0x7A0)

    private static func coordinator(_ world: FakeCrimeSessionWorld) throws -> CrimeCoordinator {
        try CrimeAlarmTests.coordinator(world, witnesses: [owner])
    }

    @Test func theCriminalAGuardAnswersCountsUntilItsAlarmEnds() throws {
        let world = FakeCrimeSessionWorld()
        world.living = [
            CrimeObserver(key: Self.owner, feet: SIMD3(1000, 0, 0)),
            CrimeObserver(key: Self.guardKey, feet: SIMD3(3000, 0, 0))
        ]
        let coordinator = try Self.coordinator(world)
        coordinator.reporter?.reportTheft(
            of: (Self.ring, 1), from: CrimeFixture.key(0x7B0), owner: .actor(Self.owner),
            by: .player
        )
        #expect(coordinator.alarm.answering[.player] == [Self.guardKey])
        #expect(coordinator.assistStanding(of: .player, judgedBy: Self.stranger) == .criminal)
    }

    @Test func theGuardCountResetsOnceNoCrimeOfTheCriminalIsLeft() {
        var alarm = CrimeAlarmState()
        let event = CrimeEvent(kind: .assault, perpetrator: Self.stranger, victim: Self.owner)
        let id = alarm.add(event, faction: Self.hold, gold: 40)
        alarm.answering[Self.stranger] = [Self.guardKey]
        alarm.answering[.player] = [Self.guardKey]
        alarm.releaseAnswering()
        #expect(alarm.answering[Self.stranger] == [Self.guardKey])
        #expect(alarm.answering[.player] == nil)
        alarm.crimes[id] = nil
        alarm.releaseAnswering()
        #expect(alarm.answering.isEmpty)
    }

    @Test func resistingArrestCountsAtOnceThenOnlyWhileAGuardFights() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world)
        coordinator.reporter?.modifyCrimeGold(by: 50, violent: false, of: Self.hold)
        coordinator.resistArrest(with: Self.hold)
        #expect(coordinator.assistStanding(of: .player, judgedBy: Self.owner) == .criminal)
        #expect(coordinator.assistStanding(of: .player, judgedBy: Self.stranger) == .clean)
        #expect(coordinator.assistStanding(of: Self.stranger, judgedBy: Self.owner) == .clean)
        world.gameSeconds = (world.gameSeconds ?? 0) + 301
        #expect(
            coordinator.assistStanding(of: .player, judgedBy: Self.owner)
                == .criminalWhileAGuardFights
        )
        #expect(coordinator.attacksPlayerOnSightForCrimes(Self.owner))
        #expect(!coordinator.attacksPlayerOnSightForCrimes(Self.stranger))
    }

    @Test func aGuardAttacksOnSightPastTheViolentLine() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world)
        #expect(coordinator.isGuard(Self.guardKey))
        #expect(!coordinator.isGuard(Self.owner))
        coordinator.reporter?.modifyCrimeGold(by: 2999, violent: true, of: Self.hold)
        #expect(!coordinator.attacksPlayerOnSightForCrimes(Self.guardKey))
        coordinator.reporter?.modifyCrimeGold(by: 1, violent: true, of: Self.hold)
        #expect(coordinator.attacksPlayerOnSightForCrimes(Self.guardKey))
    }
}
