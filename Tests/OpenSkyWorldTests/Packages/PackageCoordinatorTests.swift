// The package shell over a fake session: residency reconcile, the scheduled
// advance, and the suspend and resume latch. Synthetic records only.

import FormatsTesting
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import Testing

@MainActor
private final class FakePackageWorld: PackageWorld {
    var residents: [RuntimeReferenceEntry]? = []
    var packageClock: GameClock? = GameClock(hour: 9)
    private(set) var contextReads = 0

    func packageResidents() -> [RuntimeReferenceEntry]? {
        residents
    }

    func packageConditionContext(clock _: GameClock) -> ConditionContext {
        contextReads += 1
        return ConditionContext()
    }
}

@MainActor
struct PackageCoordinatorTests {
    private static let guardKey = PackageRuntimeFixture.key(0x500)
    private static let otherKey = PackageRuntimeFixture.key(0x501)

    @Test func reconcileDropsDepartedAndAddsArrivedInKeyOrder() {
        let change = PackageCore.reconcile(
            registered: [Self.guardKey: FormID(0x600), Self.otherKey: FormID(0x601)],
            residents: [Self.otherKey: FormID(0x602), Self.guardKey: FormID(0x600)]
        )
        #expect(change.departed.isEmpty)
        #expect(change.arrived == [PackageArrival(actor: Self.otherKey, base: FormID(0x602))])

        let empty = PackageCore.reconcile(
            registered: [Self.guardKey: FormID(0x600)],
            residents: [:]
        )
        #expect(empty.departed == [Self.guardKey])
        #expect(empty.arrived.isEmpty)
    }

    @Test func advanceRegistersResidentsAndDropsLeavers() throws {
        let (coordinator, world) = try Self.coordinator()
        world.residents = try [
            PackageRuntimeFixture.residentActor(0x500, base: 0x600),
            PackageRuntimeFixture.residentActor(0x501, base: 0x999)
        ]

        coordinator.advance()

        #expect(coordinator.registeredActors == [Self.guardKey: FormID(0x600)])
        #expect(coordinator.readout(for: Self.guardKey)?.editorID == "Morning")
        #expect(world.contextReads == 1, "one context serves every actor in one advance")

        world.residents = []
        coordinator.advance()
        #expect(coordinator.registeredActors.isEmpty)
        #expect(coordinator.readouts().isEmpty)
    }

    @Test func advanceWaitsForStreamingAndTheClock() throws {
        let (coordinator, world) = try Self.coordinator()
        world.residents = nil
        coordinator.advance()
        world.residents = try [PackageRuntimeFixture.residentActor(0x500, base: 0x600)]
        world.packageClock = nil
        coordinator.advance()
        #expect(coordinator.registeredActors.isEmpty)
    }

    @Test func resumeReselectsForTheCurrentTime() throws {
        let (coordinator, world) = try Self.coordinator()
        world.residents = try [PackageRuntimeFixture.residentActor(0x500, base: 0x600)]
        coordinator.advance()
        coordinator.suspend(Self.guardKey)
        #expect(coordinator.readout(for: Self.guardKey)?.isSuspended == true)

        world.packageClock = GameClock(hour: 13)
        coordinator.advance()
        #expect(coordinator.readout(for: Self.guardKey)?.editorID == "Morning")

        coordinator.resume(Self.guardKey)
        let readout = try #require(coordinator.readout(for: Self.guardKey))
        #expect(readout.isSuspended == false)
        #expect(readout.editorID == "Fallback")
    }

    private static func coordinator() throws -> (PackageCoordinator, FakePackageWorld) {
        let morning = try PackageRuntimeFixture.package(
            id: 0x100,
            editorID: "Morning",
            schedule: PackageFixture.scheduleValue(hour: 8, duration: 240)
        )
        let fallback = try PackageRuntimeFixture.package(id: 0x101, editorID: "Fallback")
        let actor = try PackageRuntimeFixture.actorBase(id: 0x600, packages: [0x100, 0x101])
        let coordinator = PackageCoordinator()
        coordinator.wire(store: PackageStore(
            packages: [morning, fallback],
            actorTemplates: ActorTemplateResolver(actors: [0x600: actor], leveledActors: [:])
        ))
        let world = FakePackageWorld()
        coordinator.attach(world: world)
        return (coordinator, world)
    }
}
