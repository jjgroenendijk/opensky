// The package shell over a fake session: residency reconcile, the scheduled
// advance, and the suspend and resume latch. Synthetic records only.

import FormatsTesting
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import simd
import Testing

@MainActor
private final class FakePackageWorld: PackageWorld {
    var residents: [RuntimeReferenceEntry]? = []
    var packageClock: GameClock? = GameClock(hour: 9)
    private(set) var contextReads = 0
    private(set) var moves: [SIMD3<Float>] = []
    static let place = SIMD3<Float>(100, 0, 0)

    func packageActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
        .zero
    }

    func packagePlace(
        of location: Package.Location, actor: ReferenceKey, aliasQuest: FormID?
    ) -> PackagePlace? {
        location.formID == FormID(0x700) ? PackagePlace(point: Self.place, radius: 0) : nil
    }

    func movePackageActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        moves.append(point)
        return true
    }

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

    /// A scene's travel package runs ahead of the schedule, walks the actor to its
    /// place, and is done on arrival. Clearing it hands the actor back.
    @Test func aScenePackageWalksTheActorAndEndsOnArrival() throws {
        let (coordinator, world) = try Self.coordinator()
        world.residents = try [PackageRuntimeFixture.residentActor(0x500, base: 0x600)]
        coordinator.advance()
        let owner = PackageOverrideOwner(source: FormID(0x4000), slot: 0)
        let override = PackageOverride(
            packages: [FormID(0x102)], owner: owner, aliasQuest: nil
        )

        #expect(coordinator.runOverride(override, actor: Self.guardKey) == .running)
        #expect(world.moves == [FakePackageWorld.place])
        #expect(coordinator.readout(for: Self.guardKey)?.editorID == "WalkThere")
        #expect(coordinator.readout(for: Self.guardKey)?.override == owner)

        coordinator.movementSettled(actor: Self.guardKey, reason: .arrival)
        #expect(coordinator.runOverride(override, actor: Self.guardKey) == .done)
        #expect(world.moves.count == 1, "a kept override does not start a second walk")

        coordinator.clearOverride(owner: owner, actor: Self.guardKey)
        #expect(coordinator.readout(for: Self.guardKey)?.editorID == "Morning")
        #expect(coordinator.executions.isEmpty)
        #expect(coordinator.runOverride(override, actor: Self.otherKey) == .notSimulated)
    }

    private static func coordinator() throws -> (PackageCoordinator, FakePackageWorld) {
        let morning = try PackageRuntimeFixture.package(
            id: 0x100,
            editorID: "Morning",
            schedule: PackageFixture.scheduleValue(hour: 8, duration: 240)
        )
        let fallback = try PackageRuntimeFixture.package(id: 0x101, editorID: "Fallback")
        let walk = try PackageRuntimeFixture.package(
            id: 0x102, editorID: "WalkThere", procedureNames: ["Travel"],
            dataInputs: [Package.DataInput(index: 0, type: "PLDT", value: .location(
                Package.Location(rawKind: 0, value: 0x700, radius: 0)
            ))]
        )
        let actor = try PackageRuntimeFixture.actorBase(id: 0x600, packages: [0x100, 0x101])
        let coordinator = PackageCoordinator()
        coordinator.wire(store: PackageStore(
            packages: [morning, fallback, walk],
            actorTemplates: ActorTemplateResolver(actors: [0x600: actor], leveledActors: [:])
        ))
        let world = FakePackageWorld()
        coordinator.attach(world: world)
        return (coordinator, world)
    }
}
