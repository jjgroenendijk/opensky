// The package shell over a fake session: residency reconcile, the scheduled
// advance, and the suspend and resume latch. Synthetic records only.

@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
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
    private(set) var movers: [ReferenceKey] = []
    var horse: ReferenceKey?
    var drivesPlayer = false
    static let place = SIMD3<Float>(100, 0, 0)
    static let patrol = [SIMD3<Float>(10, 0, 0), SIMD3<Float>(20, 0, 0)]

    func packageActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
        .zero
    }

    func packagePlace(
        of location: Package.Location, actor: ReferenceKey, aliasQuest: FormID?
    ) -> PackagePlace? {
        location.formID == FormID(0x700) ? PackagePlace(point: Self.place, radius: 0) : nil
    }

    func movePackageActor(_ actor: ReferenceKey, to point: SIMD3<Float>, direct _: Bool) -> Bool {
        moves.append(point)
        movers.append(actor)
        return true
    }

    func packagePatrolPath(
        from _: Package.Target, actor _: ReferenceKey, aliasQuest _: FormID?
    ) -> [SIMD3<Float>]? {
        Self.patrol
    }

    func mountPackageActor(_: ReferenceKey) -> ReferenceKey? {
        horse
    }

    func packageResidents() -> [RuntimeReferenceEntry]? {
        residents
    }

    var packageDrivesPlayer: Bool {
        drivesPlayer
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
        coordinator.advance(by: 0.5)
        #expect(coordinator.registeredActors.count == 1, "a short absence is a cell handoff")
        coordinator.advance(by: 0.5)
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

    /// A patrol that rides the actor's horse walks the horse, and the horse's arrival
    /// moves the rider's patrol on.
    @Test func aRidingPatrolWalksTheHorse() throws {
        let (coordinator, world) = try Self.coordinator()
        let horse = PackageRuntimeFixture.key(0x900)
        world.horse = horse
        world.residents = try [PackageRuntimeFixture.residentActor(0x500, base: 0x600)]
        coordinator.advance()
        let owner = PackageOverrideOwner(source: FormID(0x4000), slot: 0)
        let override = PackageOverride(packages: [FormID(0x103)], owner: owner, aliasQuest: nil)

        #expect(coordinator.runOverride(override, actor: Self.guardKey) == .running)
        #expect(coordinator.mounts[Self.guardKey] == horse)
        coordinator.movementSettled(actor: horse, reason: .arrival)

        #expect(world.movers == [horse, horse])
        #expect(world.moves == FakePackageWorld.patrol)
    }

    /// After `SetPlayerAIDriven(true)` a scene package walks the player, and the
    /// player's arrival ends it.
    @Test func aScenePackageWalksAnAIDrivenPlayer() throws {
        let (coordinator, world) = try Self.coordinator()
        world.drivesPlayer = true
        coordinator.advance()
        let owner = PackageOverrideOwner(source: FormID(0x4000), slot: 1)
        let override = PackageOverride(packages: [FormID(0x102)], owner: owner, aliasQuest: nil)

        #expect(coordinator.runOverride(override, actor: .player) == .running)
        #expect(world.movers == [.player])
        coordinator.movementSettled(actor: .player, reason: .arrival)
        #expect(coordinator.runOverride(override, actor: .player) == .done)
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
        let ride = try PackageRuntimeFixture.package(
            id: 0x103, editorID: "RidePatrol", procedureNames: ["Patrol"],
            dataInputs: [Package.DataInput(index: 0, type: "PTDA", value: .target(
                Package.Target(rawKind: 0, value: 0x701, countOrDistance: 0)
            ))] + [false, false, true, true].enumerated().map { index, flag in
                Package.DataInput(index: Int8(index + 1), type: "CNAM", value: .boolean(flag))
            }
        )
        let actor = try PackageRuntimeFixture.actorBase(id: 0x600, packages: [0x100, 0x101])
        let player = try PackageRuntimeFixture.actorBase(id: 0x7, packages: [])
        let coordinator = PackageCoordinator()
        coordinator.wire(store: PackageStore(
            packages: [morning, fallback, walk, ride],
            actorTemplates: ActorTemplateResolver(
                actors: [0x600: actor, 0x7: player], leveledActors: [:]
            )
        ))
        let world = FakePackageWorld()
        coordinator.attach(world: world)
        return (coordinator, world)
    }
}
