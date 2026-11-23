// The alarm over a fake world: a guard pursues, a victim fights, an owner takes its
// item back, and a caught pickpocket's target speaks.
// See docs/engine/crime-reports.md#the-alarm.

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
struct CrimeAlarmTests {
    private static let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
    private static let shop = CellSceneLocation.interior(FormID(0x900))
    private static let owner = CrimeFixture.key(CrimeFixture.Actors.resident)
    private static let guardKey = CrimeFixture.key(CrimeFixture.Actors.shopkeeper)
    private static let ring = FormID(0x7A0)

    private static func coordinator(
        _ world: FakeCrimeSessionWorld, witnesses: [ReferenceKey]
    ) throws -> CrimeCoordinator {
        let coordinator = try CrimeCoordinator(
            world: world,
            data: CrimeSessionData(
                runtime: CrimeFixture.runtime(),
                locations: CrimeFixture.locationStore(),
                pluginName: CrimeFixture.pluginName
            ),
            witnesses: FixedCrimeWitnesses(watching: .player, by: witnesses),
            storyEvents: nil
        )
        world.currentCellLocation = Self.shop
        world.references = FakeCrimeReferences(cell: Self.shop)
        world.cellLinks[Self.shop] = FormID(CrimeFixture.Locations.shop)
        world.playerFeet = .zero
        world.gameSeconds = 86400 * 2
        world.itemValues[Self.ring] = 100
        world.profiles[Self.owner] = ActorSocialProfile(key: Self.owner, crimeFaction: Self.hold)
        world.profiles[Self.guardKey] = ActorSocialProfile(
            key: Self.guardKey,
            memberships: CrimeFixture.state([(CrimeFixture.Factions.guards, 0)]),
            crimeFaction: Self.hold
        )
        return coordinator
    }

    private static func steal(_ coordinator: CrimeCoordinator) {
        coordinator.reporter?.reportTheft(
            of: (ring, 1), from: CrimeFixture.key(0x7B0), owner: .actor(owner),
            by: .player
        )
    }

    @Test func aGuardPursuesAndTheAssaultVictimFightsBack() throws {
        let world = FakeCrimeSessionWorld()
        world.living = [
            CrimeObserver(key: Self.owner, feet: SIMD3(100, 0, 0)),
            CrimeObserver(key: Self.guardKey, feet: SIMD3(500, 0, 0))
        ]
        let coordinator = try Self.coordinator(world, witnesses: [Self.owner])
        coordinator.reportAssault(on: Self.owner, wasHostile: false)

        #expect(coordinator.alarm.witnesses[Self.guardKey]?.role == .pursue)
        #expect(coordinator.alarm.witnesses[Self.owner]?.role == .fight)
        #expect(coordinator.alarm.fighters[Self.owner] == [.player])
        #expect(coordinator.alarm.crimes.values.first?.takenBy == Self.guardKey)

        _ = coordinator.takeCommands()
        coordinator.advanceReports(by: 3)
        #expect(coordinator.takeCommands().contains(.sayTopic("PURS", by: Self.guardKey)))
    }

    @Test func aGuardOfAnotherFactionTakesTheCrimeAndItsGold() throws {
        let world = FakeCrimeSessionWorld()
        let tolerant = CrimeFixture.key(CrimeFixture.Factions.tolerant)
        world.living = [CrimeObserver(key: Self.guardKey, feet: SIMD3(500, 0, 0))]
        let coordinator = try Self.coordinator(world, witnesses: [Self.owner])
        world.profiles[Self.guardKey] = ActorSocialProfile(
            key: Self.guardKey,
            memberships: CrimeFixture.state([(CrimeFixture.Factions.guards, 0)]),
            crimeFaction: tolerant
        )
        coordinator.reportAssault(on: Self.owner, wasHostile: false)

        #expect(coordinator.crimeGold(of: Self.hold) == 0)
        #expect(coordinator.crimeGold(of: tolerant) > 0)
        #expect(coordinator.pendingReports.map(\.faction) == [tolerant])
    }

    @Test func theOwnerWalksUpAndTakesItsItemBack() throws {
        let world = FakeCrimeSessionWorld()
        world.living = [CrimeObserver(key: Self.owner, feet: SIMD3(1000, 0, 0))]
        let coordinator = try Self.coordinator(world, witnesses: [Self.owner])
        Self.steal(coordinator)

        #expect(coordinator.alarm.witnesses[Self.owner]?.role == .takeBack)
        #expect(coordinator.takeCommands().contains(.sayTopic("STEA", by: Self.owner)))
        #expect(coordinator.crimeGold(of: Self.hold) > 0)
        #expect(coordinator.alarm.theftMark.isSet)

        coordinator.advanceReports(by: 1)
        world.living = [CrimeObserver(key: Self.owner, feet: SIMD3(50, 0, 0))]
        coordinator.advanceReports(by: 1)

        #expect(world.givenBack == [Self.owner: [Self.ring]])
        #expect(coordinator.crimeGold(of: Self.hold) == 0)
        #expect(coordinator.pendingReports.isEmpty)
        #expect(coordinator.alarm.witnesses.isEmpty)
        #expect(coordinator.lastAlarm == .tookBack(name: "Actor \(Self.owner)", items: 1))
        #expect(coordinator.alarmReadout.last == "Actor \(Self.owner) took back 1 item(s)")
    }

    @Test func aSecondTheftWithTheMarkSetMakesTheOwnerAngry() throws {
        let world = FakeCrimeSessionWorld()
        world.living = [CrimeObserver(key: Self.owner, feet: SIMD3(1000, 0, 0))]
        let coordinator = try Self.coordinator(world, witnesses: [Self.owner])
        Self.steal(coordinator)
        Self.steal(coordinator)

        #expect(coordinator.alarm.witnesses[Self.owner]?.role == .fight)
        #expect(coordinator.alarm.angry == [Self.owner])
    }

    @Test func anAggressiveOwnerThatHatesThePlayerFightsAtOnce() throws {
        let world = FakeCrimeSessionWorld()
        world.living = [CrimeObserver(key: Self.owner, feet: SIMD3(1000, 0, 0))]
        let coordinator = try Self.coordinator(world, witnesses: [Self.owner])
        world.profiles[Self.owner] = ActorSocialProfile(
            key: Self.owner, aiData: HostilityFixture.aiData(aggression: .aggressive),
            crimeFaction: Self.hold
        )
        world.reactions[Self.owner] = AlarmReactionTerms(relationship: .enemy, faction: nil)
        Self.steal(coordinator)

        let readout = coordinator.alarmReadout
        #expect(readout.witnesses.map(\.role) == ["fight"])
        #expect(readout.fighters.map(\.criminals) == [[.player]])
        #expect(readout.last == "Actor \(Self.owner): fight")
        #expect(readout.theftMarkDay == 2)
    }

    @Test func anOwnerThatCannotReachThePlayerGivesUpAndLetsItGo() throws {
        let world = FakeCrimeSessionWorld()
        world.living = [CrimeObserver(key: Self.owner, feet: SIMD3(1000, 0, 0))]
        let coordinator = try Self.coordinator(world, witnesses: [Self.owner])
        Self.steal(coordinator)
        coordinator.advanceReports(by: 21)
        coordinator.advanceReports(by: 1)

        #expect(coordinator.alarm.witnesses.isEmpty)
        #expect(world.givenBack.isEmpty)
        #expect(coordinator.crimeGold(of: Self.hold) > 0)
    }

    @Test func aWitnessInCombatOrFollowingThePlayerHearsNothing() throws {
        let world = FakeCrimeSessionWorld()
        world.living = [
            CrimeObserver(key: Self.owner, feet: SIMD3(100, 0, 0)),
            CrimeObserver(key: Self.guardKey, feet: SIMD3(500, 0, 0))
        ]
        world.fighting = [Self.guardKey]
        let coordinator = try Self.coordinator(world, witnesses: [Self.owner])
        Self.steal(coordinator)
        #expect(coordinator.alarm.witnesses[Self.guardKey] == nil)
    }

    @Test func aGuardSendsAnNPCThiefAwayAndFightsIt() throws {
        let world = FakeCrimeSessionWorld()
        let thief = CrimeFixture.key(0x7C0)
        world.living = [
            CrimeObserver(key: thief, feet: SIMD3(100, 0, 0)),
            CrimeObserver(key: Self.guardKey, feet: SIMD3(0, 0, 0))
        ]
        let coordinator = try Self.coordinator(world, witnesses: [Self.owner])
        coordinator.reportAssault(on: Self.owner, wasHostile: false, aggressor: thief)

        #expect(coordinator.alarm.fighters[Self.guardKey] == [thief])
        #expect(world.moved[thief] == SIMD3(2100, 0, 0))

        world.dead = [thief]
        coordinator.advanceReports(by: 1)
        #expect(coordinator.alarm.witnesses[Self.guardKey] == nil)
        #expect(coordinator.alarm.fighters.isEmpty)
    }
}
