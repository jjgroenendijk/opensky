// The Middle-low and Low levels of actors no loaded cell holds: which level an actor
// gets, how often each updates, and the frame budget of a pass. See
// docs/engine/ai-process-levels.md.

@testable import OpenSkyAIPackages
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import Testing

@MainActor
struct OffscreenProcessLevelTests {
    private typealias Fixture = OffscreenScheduleTests

    private static func actors(_ count: Int) -> [OffscreenActor] {
        (0 ..< count).map {
            OffscreenActor(
                key: PackageRuntimeFixture.key(0x500 + UInt32($0)), base: FormID(0x600),
                place: Fixture.house
            )
        }
    }

    @Test func aFarPersistentActorInTheLoadedWorldspaceIsMiddleLow() {
        let far = OffscreenPlace(
            location: .exterior(CellCoordinate(x: 40, y: -24)), worldspace: "Tamriel",
            point: .zero
        )
        #expect(OffscreenScheduleCore.level(of: far, residentWorldspace: "tamriel") == .middleLow)
        #expect(OffscreenScheduleCore.level(of: far, residentWorldspace: "RiftenWorld") == .low)
        #expect(OffscreenScheduleCore.level(of: far, residentWorldspace: nil) == .low)
        #expect(
            OffscreenScheduleCore.level(of: Fixture.house, residentWorldspace: "Tamriel") == .low
        )
    }

    @Test func aPassStaysInsideTheBudgetOnItsFirstFrame() throws {
        let (coordinator, world) = try Fixture.coordinator(packages: [0x102])
        world.offscreenActorList = Self.actors(25)
        world.offscreenSpent = 100
        coordinator.advance()
        #expect(coordinator.offscreen.registered.count == 10)
        #expect(coordinator.offscreen.turn.overBudgetCount == 1)
        coordinator.advance()
        #expect(coordinator.offscreen.registered.count == 20)
        coordinator.advance()
        #expect(coordinator.offscreen.registered.count == 25)
        #expect(world.offscreenMoves.count == 25)
        #expect(!coordinator.offscreen.turn.isRunning)
    }

    /// Middle-low updates every 27 game seconds at the default timescale, Low every 54.
    @Test func aMiddleLowActorUpdatesTwiceAsOftenAsALowOne() throws {
        let (coordinator, world) = try Fixture.coordinator(packages: [0x101])
        let actors = Self.actors(2)
        world.offscreenActorList = actors
        world.offscreenMiddleLow = [actors[0].key]
        coordinator.advance()
        #expect(coordinator.processReadout["middleLow"] == 1)
        #expect(coordinator.processReadout["low"] == 1)
        let first = coordinator.offscreen.steps

        let now = world.packageClock?.totalGameSeconds ?? 0
        world.packageClock = GameClock(totalGameSeconds: now + 30)
        coordinator.advance()
        let second = coordinator.offscreen.steps
        #expect(second[actors[0].key]?.gameSeconds != first[actors[0].key]?.gameSeconds)
        #expect(second[actors[1].key]?.gameSeconds == first[actors[1].key]?.gameSeconds)
    }
}
