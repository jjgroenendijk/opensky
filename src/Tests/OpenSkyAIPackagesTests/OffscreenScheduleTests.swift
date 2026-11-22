// Persistent actors no loaded cell holds keep their schedules: the update rhythm, where each
// update puts them, and the package shell that runs the pass. Synthetic records only.

@testable import OpenSkyAIPackages
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyWorldConditions
import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import Testing

@MainActor
struct OffscreenScheduleTests {
    static let actor = PackageRuntimeFixture.key(0x500)
    static let house = OffscreenPlace(
        location: .interior(FormID(0x900)), worldspace: nil, point: .zero
    )
    private static let door = OffscreenPlace(
        location: .exterior(CellCoordinate(x: 40, y: -24)), worldspace: "RiftenWorld",
        point: SIMD3(10, 0, 0)
    )

    @Test func aLowActorUpdatesEvery54GameSeconds() {
        #expect(OffscreenScheduleCore.updateSeconds() == 54)
        #expect(OffscreenScheduleCore.updateSeconds(timescale: 0) == 1080)
        #expect(OffscreenScheduleCore.isDue(now: 100, last: nil, interval: 54))
        #expect(!OffscreenScheduleCore.isDue(now: 150, last: 100, interval: 54))
        #expect(OffscreenScheduleCore.isDue(now: 154, last: 100, interval: 54))
        #expect(OffscreenScheduleCore.isDue(now: 50, last: 100, interval: 54), "clock went back")
    }

    @Test func anActorGoesStraightToAPlaceThatIsNotLoaded() {
        let stall = FakePackageWorld.stall
        #expect(OffscreenScheduleCore.decide(
            from: Self.house, to: stall, targetLoaded: false, exit: { _ in Self.door }
        ) == .place(stall))
        #expect(OffscreenScheduleCore.decide(
            from: stall, to: stall, targetLoaded: false, exit: { _ in nil }
        ) == .stays)
        let tamriel = OffscreenPlace(
            location: stall.location, worldspace: "Tamriel", point: stall.point
        )
        #expect(OffscreenScheduleCore.decide(
            from: tamriel, to: stall, targetLoaded: false, exit: { _ in nil }
        ) == .place(stall), "the same square of another worldspace is not there")
    }

    @Test func anActorLeavesItsHouseByTheDoorWhenThePlaceIsLoaded() {
        let stall = FakePackageWorld.stall
        #expect(OffscreenScheduleCore.decide(
            from: Self.house, to: stall, targetLoaded: true, exit: { _ in Self.door }
        ) == .stepOut(Self.door))
        #expect(OffscreenScheduleCore.decide(
            from: Self.house, to: stall, targetLoaded: true, exit: { _ in nil }
        ) == .place(stall))
        #expect(OffscreenScheduleCore.decide(
            from: Self.door, to: stall, targetLoaded: true, exit: { _ in Self.door }
        ) == .place(stall), "an actor outside has no door to use")
    }

    @Test func theDoorsAreSearchedOnlyWhenAnActorCanStepOut() {
        let stall = FakePackageWorld.stall
        var asked: [FormID] = []
        let exit: (FormID) -> OffscreenPlace? = { cell in
            asked.append(cell)
            return Self.door
        }
        _ = OffscreenScheduleCore.decide(
            from: Self.house,
            to: stall,
            targetLoaded: false,
            exit: exit
        )
        _ = OffscreenScheduleCore.decide(from: Self.door, to: stall, targetLoaded: true, exit: exit)
        _ = OffscreenScheduleCore.decide(from: stall, to: stall, targetLoaded: true, exit: exit)
        #expect(asked.isEmpty)
        _ = OffscreenScheduleCore.decide(
            from: Self.house,
            to: stall,
            targetLoaded: true,
            exit: exit
        )
        #expect(asked == [FormID(0x900)])
    }

    @Test func theReadoutNamesTheStepPackageCellAndHour() {
        let step = OffscreenStep(
            kind: .placed, package: FormID(0x102), place: FakePackageWorld.stall,
            gameSeconds: 86400 * 3 + 37800
        )
        #expect(step.readout.hasPrefix("placed package "))
        #expect(step.readout.contains("RiftenWorld"))
        #expect(step.readout.hasSuffix("at 10.5"))
        let none = OffscreenStep(kind: .stays, package: nil, place: nil, gameSeconds: 0)
        #expect(none.readout == "stays no package at 0.0")
    }

    @Test func aPassPutsAnUnloadedActorAtItsPackagePlaceOncePerUpdate() throws {
        let (coordinator, world) = try Self.coordinator(packages: [0x102])
        world.offscreenActorList = [OffscreenActor(
            key: Self.actor, base: FormID(0x600), place: Self.house
        )]
        coordinator.advance()
        #expect(world.offscreenMoves.map(\.place) == [FakePackageWorld.stall])
        #expect(coordinator.offscreen.steps[Self.actor]?.kind == .placed)
        #expect(coordinator.offscreenReadout(for: Self.actor)?.hasPrefix("placed") == true)

        coordinator.advance()
        #expect(world.offscreenMoves.count == 1, "the next update is not due yet")

        world.offscreenActorList = [OffscreenActor(
            key: Self.actor, base: FormID(0x600), place: FakePackageWorld.stall
        )]
        world.packageClock = GameClock(hour: 10)
        coordinator.advance()
        #expect(world.offscreenMoves.count == 1)
        #expect(coordinator.offscreen.steps[Self.actor]?.kind == .stays)

        world.offscreenActorList = []
        world.packageClock = GameClock(hour: 11)
        coordinator.advance()
        #expect(coordinator.offscreen.registered.isEmpty)
        #expect(coordinator.offscreenReadout(for: Self.actor) == nil)
    }

    @Test func aSitPackageNamesItsPlaceByItsSeat() throws {
        let (coordinator, world) = try Self.coordinator(packages: [0x103])
        world.offscreenActorList = [OffscreenActor(
            key: Self.actor, base: FormID(0x600), place: Self.house
        )]
        coordinator.advance()
        #expect(world.offscreenMoves.map(\.place) == [FakePackageWorld.stall])
    }

    @Test func aSitPackageNamesItsPlaceByALinkedSeat() throws {
        let (coordinator, world) = try Self.coordinator(packages: [0x104])
        world.offscreenActorList = [OffscreenActor(
            key: Self.actor, base: FormID(0x600), place: Self.house
        )]
        coordinator.advance()
        #expect(world.offscreenMoves.map(\.place) == [FakePackageWorld.stall])
    }

    @Test func aLoadedPlaceIsReachedThroughTheHouseDoor() throws {
        let (coordinator, world) = try Self.coordinator(packages: [0x102])
        world.offscreenActorList = [OffscreenActor(
            key: Self.actor, base: FormID(0x600), place: Self.house
        )]
        world.offscreenLoaded = true
        world.offscreenExit = Self.door
        coordinator.advance()
        #expect(world.offscreenMoves.map(\.place) == [Self.door])
        #expect(coordinator.offscreen.steps[Self.actor]?.kind == .steppedOut)
    }

    @Test func aLoadedActorOrOneWithoutAPlaceIsNotMoved() throws {
        let (coordinator, world) = try Self.coordinator(packages: [0x101])
        world.offscreenActorList = [
            OffscreenActor(key: Self.actor, base: FormID(0x600), place: Self.house),
            OffscreenActor(
                key: PackageRuntimeFixture.key(0x501), base: FormID(0x600), place: Self.house
            )
        ]
        world.residents = try [PackageRuntimeFixture.residentActor(0x501, base: 0x600)]
        coordinator.advance()
        #expect(world.offscreenMoves.isEmpty)
        #expect(coordinator.offscreen.steps[Self.actor]?.kind == .stays)
        #expect(coordinator.offscreen.steps[Self.actor]?.place == nil)
        #expect(coordinator.processReadout["low"] == 1)
        #expect(coordinator.processReadout["middleHigh"] == 0)
        #expect(coordinator.offscreen.registered.keys.sorted() == [Self.actor])
    }

    @Test func aNewGamePutsEveryActorStraightAtItsPackagePlace() throws {
        let (coordinator, world) = try Self.coordinator(packages: [0x102])
        let loaded = PackageRuntimeFixture.key(0x501)
        world.offscreenActorList = [
            OffscreenActor(key: Self.actor, base: FormID(0x600), place: Self.house),
            OffscreenActor(key: loaded, base: FormID(0x600), place: Self.house)
        ]
        world.residents = try [PackageRuntimeFixture.residentActor(0x501, base: 0x600)]
        world.offscreenLoaded = true
        world.offscreenExit = Self.door
        coordinator.placeActorsAtPackagePlaces()
        #expect(coordinator.placementDue)
        coordinator.advance()
        #expect(!coordinator.placementDue)
        let placed = world.offscreenMoves.prefix(2)
        #expect(placed.map(\.actor) == [Self.actor, loaded])
        #expect(placed.allSatisfy { $0.place == FakePackageWorld.stall })
        #expect(coordinator.offscreen.registered.keys.sorted() == [Self.actor])

        let moves = world.offscreenMoves.count
        coordinator.advance()
        #expect(world.offscreenMoves.count == moves, "the placement runs once")
    }

    @Test func aPlacementLeavesAFightingActorWhereItIs() throws {
        let (coordinator, world) = try Self.coordinator(packages: [0x102])
        let loaded = PackageRuntimeFixture.key(0x501)
        world.offscreenActorList = [
            OffscreenActor(key: loaded, base: FormID(0x600), place: Self.house)
        ]
        world.residents = try [PackageRuntimeFixture.residentActor(0x501, base: 0x600)]
        coordinator.advance()
        world.activity = .fighting
        coordinator.placeActorsAtPackagePlaces()
        coordinator.advance()
        #expect(world.offscreenMoves.isEmpty)
        #expect(!coordinator.placementDue)
    }

    @Test func anActorOfACellThatLoadsStartsAtItsPackagePlace() throws {
        let (coordinator, world) = try Self.coordinator(packages: [0x104])
        let loaded = PackageRuntimeFixture.key(0x501)
        world.offscreenArrivals = [
            loaded: OffscreenActor(key: loaded, base: FormID(0x600), place: Self.house)
        ]
        world.residents = try [PackageRuntimeFixture.residentActor(0x501, base: 0x600)]
        coordinator.advance()
        #expect(world.offscreenMoves.map(\.actor) == [loaded])
        #expect(world.offscreenMoves.map(\.place) == [FakePackageWorld.stall])

        coordinator.advance()
        #expect(world.offscreenMoves.count == 1, "an actor arrives once")
    }

    @Test func aQuestAliasPackageGoesBeforeTheActorsOwn() throws {
        let (coordinator, world) = try Self.coordinator(packages: [0x101])
        world.offscreenActorList = [OffscreenActor(
            key: Self.actor, base: FormID(0x600), place: Self.house
        )]
        world.aliasStacks = [
            Self.actor: PackageAliasStack(packages: [FormID(0x102)], quest: FormID(0x900))
        ]
        coordinator.advance()
        #expect(world.offscreenMoves.map(\.place) == [FakePackageWorld.stall])
        #expect(coordinator.offscreen.steps[Self.actor]?.package == FormID(0x102))
    }

    static func coordinator(
        packages: [UInt32]
    ) throws -> (PackageCoordinator, FakePackageWorld) {
        let fallback = try PackageRuntimeFixture.package(id: 0x101, editorID: "Fallback")
        let walk = try PackageRuntimeFixture.package(
            id: 0x102, editorID: "WorkAtStall", procedureNames: ["Travel"],
            dataInputs: [Package.DataInput(index: 0, type: "PLDT", value: .location(
                Package.Location(rawKind: 0, value: 0x700, radius: 0)
            ))]
        )
        let sit = try PackageRuntimeFixture.package(
            id: 0x103, editorID: "SitAtStall", procedureNames: ["Sit"],
            dataInputs: [Package.DataInput(index: 0, type: "SingleRef", value: .target(
                Package.Target(rawKind: 0, value: 0x700, countOrDistance: 0)
            ))]
        )
        let post = try PackageRuntimeFixture.package(
            id: 0x104, editorID: "SitAtPost", procedureNames: ["Sit"],
            dataInputs: [Package.DataInput(index: 0, type: "SingleRef", value: .target(
                Package.Target(rawKind: 3, value: 0x700, countOrDistance: 0)
            ))]
        )
        let actor = try PackageRuntimeFixture.actorBase(id: 0x600, packages: packages)
        let world = FakePackageWorld()
        let coordinator = PackageCoordinator(
            world: world,
            data: PackageSessionData(store: PackageStore(
                packages: [fallback, walk, sit, post],
                actorTemplates: ActorTemplateResolver(actors: [0x600: actor], leveledActors: [:])
            ), conditionFunctions: .standard)
        )
        return (coordinator, world)
    }
}
