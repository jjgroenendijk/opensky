// The crime shell over a fake world: the assault, murder, and trespass hooks,
// one guard tick, and the panel's bounty and membership controls. The
// sentences and lists are tested in `CrimeCoreTests`.

@testable import OpenSkyCrime
import OpenSkyCrimeFixtures
@testable import OpenSkyCrimeInterface
import OpenSkyCrimeTesting
@testable import OpenSkyFactionsInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorldState
import Testing

@MainActor
struct CrimeCoordinatorTests {
    private static let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
    private static let guards = CrimeFixture.key(CrimeFixture.Factions.guards)
    private static let shop = CellSceneLocation.interior(FormID(0x900))
    private static let victim = CrimeFixture.key(CrimeFixture.Actors.resident)
    private static let guardKey = CrimeFixture.key(CrimeFixture.Actors.shopkeeper)

    /// A coordinator whose every cell sits in the hold, watched by one witness.
    private static func coordinator(
        _ world: FakeCrimeSessionWorld
    ) throws -> CrimeCoordinator {
        let coordinator = CrimeCoordinator()
        coordinator.attach(world: world)
        try coordinator.wire(
            runtime: CrimeFixture.runtime(),
            locations: CrimeFixture.locationStore(),
            pluginName: CrimeFixture.pluginName
        )
        coordinator.attachWitnesses(FixedCrimeWitnesses(watching: .player, by: [Self.victim]))
        world.currentCellLocation = Self.shop
        world.references = FakeCrimeReferences(cell: Self.shop)
        world.cellLinks[Self.shop] = FormID(CrimeFixture.Locations.shop)
        return coordinator
    }

    @Test func onlyTheFirstBlowOfAFightIsAnAssault() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world)
        coordinator.reportAssault(on: Self.victim, wasHostile: false)
        let first = coordinator.crimeGold(of: Self.hold)
        coordinator.reportAssault(on: Self.victim, wasHostile: false)

        #expect(first > 0)
        #expect(coordinator.crimeGold(of: Self.hold) == first)
        #expect(coordinator.lastActionText.hasPrefix("Assault: \(first) bounty with"))
    }

    @Test func selfDefenseAndAnotherAggressorAreNoCrime() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world)
        coordinator.reportAssault(on: Self.victim, wasHostile: true)
        coordinator.reportAssault(on: Self.victim, wasHostile: false, aggressor: Self.guardKey)
        coordinator.reportMurder(of: Self.victim)

        #expect(coordinator.crimeGold(of: Self.hold) == 0)
    }

    @Test func aDeathIsMurderOnlyAfterThePlayerStruckFirst() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world)
        coordinator.reportAssault(on: Self.victim, wasHostile: false)
        let assault = coordinator.crimeGold(of: Self.hold)
        coordinator.reportMurder(of: Self.victim)

        #expect(coordinator.crimeGold(of: Self.hold) > assault)
        #expect(coordinator.lastActionText.hasPrefix("Murder:"))
    }

    @Test func trespassIsNoticedOnceOnArrival() throws {
        let world = FakeCrimeSessionWorld()
        world.cellOwners[Self.shop] = RecordOwnership(owner: FormID(CrimeFixture.Factions.hold))
        let coordinator = try Self.coordinator(world)
        coordinator.advanceTrespass()
        let charged = coordinator.lastActionText
        coordinator.advanceTrespass()

        #expect(charged.hasPrefix("Trespass:"))
        #expect(coordinator.lastActionText == charged)
    }

    @Test func aDetectingGuardWithNoDialogueIsHeldOffAndResumed() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world)
        coordinator.reporter?.runtime.setCrimeGold(100, of: Self.hold)
        world.gameSeconds = 0
        world.playerFeet = .zero
        world.observers = [CrimeObserver(key: Self.guardKey, feet: [10, 0, 0])]
        world.profiles[Self.guardKey] = ActorSocialProfile(
            key: Self.guardKey,
            memberships: CrimeFixture.state([(CrimeFixture.Factions.guards, 0)]),
            crimeFaction: Self.hold
        )
        coordinator.advanceGuardResponse()

        #expect(world.spokenTo == [Self.guardKey])
        #expect(world.resumed == [Self.guardKey])
        #expect(coordinator.lastGuardText.hasPrefix("Guard could not open"))
        #expect(world.guardHostility?.bounties == [Self.hold: 100])
    }

    @Test func aFarGuardPursuesAndRepathsOnlyWhenThePlayerMoves() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world)
        coordinator.reporter?.runtime.setCrimeGold(100, of: Self.hold)
        world.gameSeconds = 0
        world.playerFeet = .zero
        world.observers = [CrimeObserver(key: Self.guardKey, feet: [5000, 0, 0])]
        world.profiles[Self.guardKey] = ActorSocialProfile(
            key: Self.guardKey,
            memberships: CrimeFixture.state([(CrimeFixture.Factions.guards, 0)]),
            crimeFaction: Self.hold
        )
        coordinator.advanceGuardResponse()

        #expect(world.moved[Self.guardKey] == .zero)
        #expect(world.suspended.contains(Self.guardKey))
        #expect(coordinator.lastGuardText.contains("pursuing"))
    }

    @Test func thePanelMovesAndClearsTheSelectedBounty() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world)
        coordinator.bountyFactionSelection = Self.hold
        coordinator.modifySelectedBounty(by: 1500, violent: true)
        #expect(coordinator.crimeGold(of: Self.hold) == 1500)
        #expect(world.guardHostility?.bounties == [Self.hold: 1500])

        let text = coordinator.clearSelectedBounty()
        #expect(text == "Cleared 1500 gold owed to CrimeFactionHold.")
        #expect(coordinator.crimeFactionSnapshot.lastActionText == text)
    }

    @Test func resistingTurnsTheHoldsGuardsAgainstThePlayer() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world)
        let text = coordinator.resistArrestWithSelectedFaction()
        #expect(text == "Resisted arrest with CrimeFactionHold.")
        #expect(coordinator.guards.resisted == [Self.hold])
        #expect(world.guardHostility?.resisted == [Self.hold])
    }

    @Test func joinAndLeaveActOnThePlayerByDefault() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world)
        coordinator.membershipFactionSelection = Self.guards
        #expect(coordinator.joinSelectedFaction(rank: 1)
            == "The player is in GuardFaction at rank 1.")
        #expect(world.memberships[.player]?.isMember(of: Self.guards) == true)
        #expect(coordinator.leaveSelectedFaction() == "The player left GuardFaction.")
    }

    @Test func withoutFactionDataThePanelIsUnavailable() throws {
        let world = FakeCrimeSessionWorld()
        world.hasFactionData = false
        let coordinator = try Self.coordinator(world)
        #expect(!coordinator.crimeFactionSnapshot.isAvailable)
        #expect(coordinator.joinSelectedFaction(rank: 0)
            == CrimeFactionControlSnapshot.unavailable.lastActionText)
    }
}
