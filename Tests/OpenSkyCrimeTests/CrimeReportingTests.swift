// Trespass warnings, the reporting chain from witness to guard, and the jail stay,
// over a fake world.

import OpenSkyConditions
@testable import OpenSkyCrime
import OpenSkyCrimeFixtures
@testable import OpenSkyCrimeInterface
@testable import OpenSkyFactionsInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventoryInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct CrimeReportingTests {
    private typealias Items = InventoryBaselineFixture

    private static let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
    private static let shop = CellSceneLocation.interior(FormID(0x900))
    private static let jail = CellSceneLocation.interior(FormID(0x950))
    private static let victim = CrimeFixture.key(CrimeFixture.Actors.resident)
    private static let guardKey = CrimeFixture.key(CrimeFixture.Actors.shopkeeper)
    private static let belongings = CrimeFixture.key(CrimeFixture.Links.belongingsChest)
    private static let marker = CrimeFixture.key(CrimeFixture.Links.jailMarker)

    private static func coordinator(
        _ world: FakeCrimeSessionWorld, witnesses: [ReferenceKey] = [victim]
    ) throws -> CrimeCoordinator {
        let coordinator = CrimeCoordinator(world: world)
        try coordinator.wire(
            runtime: CrimeFixture.runtime(),
            locations: CrimeFixture.locationStore(),
            pluginName: CrimeFixture.pluginName
        )
        coordinator.attachWitnesses(FixedCrimeWitnesses(watching: .player, by: witnesses))
        world.currentCellLocation = Self.shop
        world.references = FakeCrimeReferences(cell: Self.shop)
        world.cellLinks[Self.shop] = FormID(CrimeFixture.Locations.shop)
        world.profiles[Self.guardKey] = ActorSocialProfile(
            key: Self.guardKey,
            memberships: CrimeFixture.state([(CrimeFixture.Factions.guards, 0)]),
            crimeFaction: Self.hold
        )
        return coordinator
    }

    // MARK: - Trespass

    @Test func trespassWarnsTwiceThenChargesAfterTheGracePeriod() throws {
        let world = FakeCrimeSessionWorld()
        world.cellOwners[Self.shop] = RecordOwnership(owner: FormID(CrimeFixture.Factions.hold))
        let coordinator = try Self.coordinator(world)
        coordinator.advanceTrespass(by: 0)
        #expect(coordinator.lastCrime == .trespassWarning(secondsLeft: 30))
        coordinator.advanceTrespass(by: 15)
        #expect(coordinator.lastCrime == .trespassWarning(secondsLeft: 15))
        #expect(coordinator.crimeGold(of: Self.hold) == 0)

        coordinator.advanceTrespass(by: 15)
        let charged = coordinator.crimeGold(of: Self.hold)
        coordinator.advanceTrespass(by: 60)

        #expect(coordinator.lastCrime.text.hasPrefix("Trespass:"))
        #expect(charged > 0)
        #expect(coordinator.crimeGold(of: Self.hold) == charged)
        #expect(coordinator.takeCommands().contains(.incrementStat("Trespasses", by: 1)))
    }

    @Test func anOffLimitsCellChargesWithNoWarningAndAPublicOneNever() throws {
        let world = FakeCrimeSessionWorld()
        world.cellOwners[Self.shop] = RecordOwnership(owner: FormID(CrimeFixture.Factions.hold))
        world.trespassFlags[Self.shop] = CellTrespassFlags(isOffLimits: true)
        let coordinator = try Self.coordinator(world)
        coordinator.advanceTrespass(by: 0)
        #expect(coordinator.lastCrime.text.hasPrefix("Trespass:"))

        let open = FakeCrimeSessionWorld()
        open.cellOwners[Self.shop] = RecordOwnership(owner: FormID(CrimeFixture.Factions.hold))
        open.trespassFlags[Self.shop] = CellTrespassFlags(isPublicArea: true)
        let inn = try Self.coordinator(open)
        inn.advanceTrespass(by: 60)
        #expect(inn.lastCrime == .idle)
        #expect(!inn.isPlayerTrespassing)
    }

    // MARK: - Reporting chain

    @Test func aCrimeWhoseOnlyWitnessDiesCostsNothing() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world)
        coordinator.reportAssault(on: Self.victim, wasHostile: false)
        #expect(coordinator.crimeGold(of: Self.hold) > 0)
        #expect(coordinator.pendingReports.count == 1)

        world.dead = [Self.victim]
        coordinator.advanceReports()

        #expect(coordinator.crimeGold(of: Self.hold) == 0)
        #expect(coordinator.pendingReports.isEmpty)
        #expect(coordinator.lastCrime.text.hasPrefix("Every witness died"))
    }

    @Test func aWitnessNearAGuardDeliversTheReport() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world)
        coordinator.reportAssault(on: Self.victim, wasHostile: false)
        let gold = coordinator.crimeGold(of: Self.hold)
        world.living = [
            CrimeObserver(key: Self.victim, feet: .zero),
            CrimeObserver(key: Self.guardKey, feet: [100, 0, 0])
        ]
        coordinator.advanceReports()
        world.dead = [Self.victim]
        coordinator.advanceReports()

        #expect(coordinator.pendingReports.isEmpty)
        #expect(coordinator.crimeGold(of: Self.hold) == gold)
    }

    @Test func aGuardThatSawTheCrimeReportsItAtOnce() throws {
        let world = FakeCrimeSessionWorld()
        let coordinator = try Self.coordinator(world, witnesses: [Self.guardKey])
        coordinator.reportAssault(on: Self.victim, wasHostile: false)

        #expect(coordinator.crimeGold(of: Self.hold) > 0)
        #expect(coordinator.pendingReports.isEmpty)
    }

    // MARK: - Jail

    private static func jailedWorld() throws -> (FakeCrimeSessionWorld, FakeCrimeInventory) {
        let world = FakeCrimeSessionWorld()
        let inventory = try FakeCrimeInventory()
        try inventory.add(Items.gold, count: 50, to: .player)
        try inventory.add(Items.lockpick, count: 3, to: .player)
        try inventory.add(Items.sword, count: 1, to: .player)
        world.inventory = inventory
        world.jailCell = Self.jail
        world.lockpick = Items.lockpick
        world.gameSeconds = 0
        return (world, inventory)
    }

    @Test func aSentenceIsServedInTheCellAndGivesTheBelongingsBack() throws {
        let (world, inventory) = try Self.jailedWorld()
        let coordinator = try Self.coordinator(world)
        coordinator.reporter?.runtime.setCrimeGold(300, of: Self.hold)
        _ = coordinator.settleArrest(with: Self.hold, .jail)

        let stay = try #require(coordinator.jailStay)
        #expect(stay.sentenceDays == 3)
        #expect(world.gameSeconds == 0)
        #expect(inventory.counts[.player] == [Items.lockpick: 1])
        #expect(inventory.counts[Self.belongings]?[Items.sword] == 1)
        #expect(coordinator.crimeGold(of: Self.hold) == 0)

        world.currentCellLocation = Self.jail
        coordinator.advanceJail()
        #expect(coordinator.serveSentence())

        #expect(coordinator.jailStay == nil)
        #expect(world.gameSeconds == Double(3 * 86400))
        #expect(inventory.count(of: Items.lockpick, in: .player) == 3)
        #expect(inventory.goldCount(of: .player) == 50)
        #expect(world.leftJail == [Self.marker])
        #expect(world.lostProgress.map(\.days) == [3])
        let commands = coordinator.takeCommands()
        #expect(commands.contains(.incrementStat("Times Jailed", by: 1)))
        #expect(commands.contains(.incrementStat("Days Jailed", by: 3)))
    }

    @Test func leavingTheCellIsAnEscapeThatOwesTheBountyAgain() throws {
        let (world, _) = try Self.jailedWorld()
        let coordinator = try Self.coordinator(world)
        let recorder = StoryEventRecorder()
        coordinator.storyEvents = recorder
        let runtime = try #require(coordinator.reporter?.runtime)
        runtime.setCrimeGold(300, of: Self.hold)
        _ = coordinator.settleArrest(with: Self.hold, .jail)
        world.currentCellLocation = Self.jail
        coordinator.advanceJail()
        #expect(coordinator.jailStay != nil)

        world.currentCellLocation = Self.shop
        coordinator.advanceJail()

        let escape = runtime.prices(of: Self.hold)?.escape ?? runtime.settings.defaultPrices.escape
        #expect(coordinator.jailStay == nil)
        #expect(coordinator.crimeGold(of: Self.hold) == 300 + escape)
        #expect(recorder.events("ESJA").count == 1)
        #expect(!coordinator.serveSentence())
    }

    @Test func withoutACellTheSentencePassesAtOnce() throws {
        let (world, _) = try Self.jailedWorld()
        world.jailCell = nil
        let coordinator = try Self.coordinator(world)
        coordinator.reporter?.runtime.setCrimeGold(300, of: Self.hold)
        _ = coordinator.settleArrest(with: Self.hold, .jail)

        #expect(coordinator.jailStay == nil)
        #expect(world.gameSeconds == Double(3 * 86400))
    }

    @Test func theStayBeginsInTheFirstCellAfterTheArrest() {
        var stay = JailStay(
            faction: Self.hold, nonViolentGold: 10, violentGold: 0, sentenceDays: 1,
            exteriorMarker: Self.marker, belongings: nil, outfit: [], arrestedIn: Self.shop
        )
        #expect(stay.step(playerCell: Self.shop) == .waiting)
        #expect(stay.step(playerCell: nil) == .waiting)
        #expect(stay.step(playerCell: Self.jail) == .arrived)
        #expect(stay.step(playerCell: Self.jail) == .waiting)
        #expect(stay.step(playerCell: Self.shop) == .escaped)
    }
}

struct TrespassWatchTests {
    @Test func theOwnerWaitsTheWarningTimerAfterALateWarning() {
        var settings = CrimeSettings()
        settings.trespassGraceSeconds = 10
        settings.trespassWarnings = 2
        settings.trespassCallGuardsSeconds = 5
        var watch = TrespassWatch()
        #expect(watch.step(seconds: 0, seen: true, offLimits: false, settings: settings)
            == .warn(remaining: 10))
        #expect(watch.step(seconds: 6, seen: true, offLimits: false, settings: settings)
            == .warn(remaining: 5))
        #expect(watch.step(seconds: 4, seen: true, offLimits: false, settings: settings) == .none)
        #expect(watch.step(seconds: 1, seen: true, offLimits: false, settings: settings) == .charge)
    }

    @Test func theWarningTimerSpacesTwoWarnings() {
        var settings = CrimeSettings()
        settings.trespassGraceSeconds = 10
        settings.trespassWarnings = 2
        settings.trespassWarningInterval = 8
        var watch = TrespassWatch()
        _ = watch.step(seconds: 0, seen: true, offLimits: false, settings: settings)
        #expect(watch.step(seconds: 6, seen: true, offLimits: false, settings: settings) == .none)
        #expect(watch.step(seconds: 2, seen: true, offLimits: false, settings: settings)
            == .warn(remaining: 5))
    }

    @Test func aWarningTimerPastTheGraceLeavesOneWarning() {
        var settings = CrimeSettings()
        settings.trespassGraceSeconds = 10
        settings.trespassWarnings = 3
        settings.trespassWarningInterval = 12
        var watch = TrespassWatch()
        _ = watch.step(seconds: 0, seen: true, offLimits: false, settings: settings)
        #expect(watch.step(seconds: 9, seen: true, offLimits: false, settings: settings) == .none)
        #expect(watch.warnings == 1)
    }
}
