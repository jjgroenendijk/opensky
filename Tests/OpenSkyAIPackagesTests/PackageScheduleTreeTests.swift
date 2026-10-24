// The procedure tree of the package an actor's own schedule picks: it runs, stops on a
// new pick, waits during fights and conversations, and queues for mover slots.
// Synthetic records only.

@testable import OpenSkyAIPackages
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import Testing

@MainActor
struct PackageScheduleTreeTests {
    private static let guardKey = PackageRuntimeFixture.key(0x500)
    private static let otherKey = PackageRuntimeFixture.key(0x501)
    private static let scene = PackageOverride(
        packages: [FormID(0x102)],
        owner: PackageOverrideOwner(source: FormID(0x4000), slot: 0), aliasQuest: nil
    )

    @Test func aSchedulePackageWalksAndStopsWhenThePickChanges() throws {
        let (coordinator, world) = try Self.coordinator(base: 0x610)
        coordinator.advance()
        #expect(world.moves == [FakePackageWorld.place])
        #expect(coordinator.executions[Self.guardKey]?.fromSchedule == true)

        world.packageClock = GameClock(hour: 13)
        coordinator.advance(by: 0.1)
        #expect(coordinator.readout(for: Self.guardKey)?.editorID == "Linger")
        #expect(world.scriptEvents == [.begin, .change, .begin])
        #expect(world.stops == [Self.guardKey])
    }

    @Test func aScenePackageWinsAndTheScheduleTreeResumes() throws {
        let (coordinator, world) = try Self.coordinator(base: 0x610)
        coordinator.advance()
        #expect(coordinator.runOverride(Self.scene, actor: Self.guardKey) == .running)
        #expect(coordinator.executions[Self.guardKey]?.fromSchedule == false)

        coordinator.clearOverride(owner: Self.scene.owner, actor: Self.guardKey)
        coordinator.advance(by: 0.1)
        #expect(coordinator.executions[Self.guardKey]?.fromSchedule == true)
        #expect(world.scriptEvents == [.begin, .change, .begin, .change, .begin])
        #expect(world.moves.count == 3)
    }

    @Test func aFightOrAConversationPausesTheScheduleTree() throws {
        let (coordinator, world) = try Self.coordinator(base: 0x610)
        coordinator.advance()
        world.activity = .fighting
        coordinator.advance(by: 0.1)
        #expect(coordinator.executions[Self.guardKey] == nil)
        #expect(world.stops.isEmpty, "the fight moves the actor now")

        world.activity = .free
        coordinator.advance(by: 0.1)
        #expect(world.moves.count == 2)

        coordinator.suspend(Self.guardKey)
        coordinator.advance(by: 0.1)
        #expect(coordinator.executions[Self.guardKey] == nil)
        #expect(world.stops == [Self.guardKey])
        coordinator.resume(Self.guardKey)
        #expect(coordinator.executions[Self.guardKey] != nil)
        #expect(world.scriptEvents == [.begin, .change, .begin, .change, .begin])
    }

    @Test func aMustCompletePackageOutlastsItsSchedule() throws {
        let (coordinator, world) = try Self.coordinator(base: 0x611)
        coordinator.advance()
        world.packageClock = GameClock(hour: 13)
        coordinator.advance(by: 0.1)
        #expect(coordinator.readout(for: Self.guardKey)?.editorID == "MustWork")

        coordinator.movementSettled(actor: Self.guardKey, reason: .arrival)
        coordinator.advance(by: 0.1)
        #expect(coordinator.readout(for: Self.guardKey)?.editorID == "Linger")
    }

    @Test func aOncePerDayPackageIsNotPickedAgainThatDay() throws {
        let (coordinator, world) = try Self.coordinator(base: 0x612)
        coordinator.advance()
        #expect(coordinator.readout(for: Self.guardKey)?.editorID == "Daily")
        coordinator.movementSettled(actor: Self.guardKey, reason: .arrival)
        coordinator.advance(by: 0.1)
        #expect(coordinator.readout(for: Self.guardKey)?.editorID == "Linger")

        world.packageClock = GameClock(hour: 20)
        coordinator.evaluate(Self.guardKey)
        #expect(coordinator.readout(for: Self.guardKey)?.editorID == "Linger")

        world.packageClock = GameClock(
            totalGameSeconds: GameClock(hour: 10).totalGameSeconds + GameClock.secondsPerDay
        )
        coordinator.evaluate(Self.guardKey)
        #expect(coordinator.readout(for: Self.guardKey)?.editorID == "Daily")
    }

    /// No path is searched while every slot is taken. A scene walk then goes first.
    @Test func waitingWalksQueueWithSceneWalksFirst() throws {
        let (coordinator, world) = try Self.coordinator(base: 0x610)
        world.residents = try [0x500, 0x501].map {
            try PackageRuntimeFixture.residentActor($0, base: 0x610)
        }
        world.hasRoom = false
        coordinator.advance()
        #expect(world.moves.isEmpty)
        #expect(coordinator.waitingMoves.count == 2)

        #expect(coordinator.runOverride(Self.scene, actor: Self.otherKey) == .running)
        world.hasRoom = true
        coordinator.advance(by: 0.1)
        #expect(world.movers == [Self.otherKey, Self.guardKey])
        #expect(coordinator.waitingMoves.isEmpty)
    }

    @Test func aSandboxAtAnIdleMarkerLeavesTheWalkToTheIdleRuntime() throws {
        let (coordinator, world) = try Self.coordinator(base: 0x613)
        world.holdsIdleMarker = true
        coordinator.advance()
        coordinator.advance(by: 5)
        #expect(world.moves.isEmpty)
        #expect(coordinator.executions[Self.guardKey]?.machine?.kind == .sandbox)
    }

    @Test func restartStartsTheTreeFromItsRoot() throws {
        let (coordinator, world) = try Self.coordinator(base: 0x610)
        coordinator.advance()
        coordinator.restart(Self.guardKey)
        #expect(world.scriptEvents == [.begin, .change, .begin])
        #expect(world.moves.count == 2)
    }

    private static func coordinator(
        base: UInt32
    ) throws -> (PackageCoordinator, FakePackageWorld) {
        let place = [Package.DataInput(index: 0, type: "PLDT", value: .location(
            Package.Location(rawKind: 0, value: 0x700, radius: 0)
        ))]
        let work = PackageFixture.scheduleValue(hour: 8, duration: 240)
        let packages = try [
            PackageRuntimeFixture.package(
                id: 0x102, editorID: "WalkThere", procedureNames: ["Travel"], dataInputs: place
            ),
            PackageRuntimeFixture.package(
                id: 0x110, editorID: "GoToWork", schedule: work, procedureNames: ["Travel"],
                dataInputs: place
            ),
            PackageRuntimeFixture.package(id: 0x111, editorID: "Linger", procedureNames: ["Wait"]),
            PackageRuntimeFixture.package(
                id: 0x112, editorID: "MustWork", schedule: work, procedureNames: ["Travel"],
                dataInputs: place, flags: .mustComplete
            ),
            PackageRuntimeFixture.package(
                id: 0x113, editorID: "Daily", procedureNames: ["Travel"], dataInputs: place,
                flags: .oncePerDay
            ),
            PackageRuntimeFixture.package(
                id: 0x114, editorID: "Loiter", procedureNames: ["Sandbox"], dataInputs: place
            )
        ]
        let actors: [UInt32: ActorBase] = try [
            0x610: PackageRuntimeFixture.actorBase(id: 0x610, packages: [0x110, 0x111]),
            0x611: PackageRuntimeFixture.actorBase(id: 0x611, packages: [0x112, 0x111]),
            0x612: PackageRuntimeFixture.actorBase(id: 0x612, packages: [0x113, 0x111]),
            0x613: PackageRuntimeFixture.actorBase(id: 0x613, packages: [0x114])
        ]
        let world = FakePackageWorld()
        world.residents = try [PackageRuntimeFixture.residentActor(0x500, base: base)]
        let coordinator = PackageCoordinator(
            world: world,
            data: PackageSessionData(store: PackageStore(
                packages: packages,
                actorTemplates: ActorTemplateResolver(actors: actors, leveledActors: [:])
            ))
        )
        return (coordinator, world)
    }
}
