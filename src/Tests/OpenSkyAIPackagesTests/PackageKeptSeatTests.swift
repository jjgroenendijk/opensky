// A seated actor whose package changes: a next package that sits in the same seat keeps
// the actor seated, and one that goes elsewhere gets it up. Synthetic records only.

@testable import OpenSkyAIPackages
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import OpenSkyWorldConditions
import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import simd
import Testing

@MainActor
struct PackageKeptSeatTests {
    private static let actor = PackageRuntimeFixture.key(0x500)
    private static let block = PackageRuntimeFixture.key(0x900)
    private static let seat = PackageSeat(
        furniture: block, index: 0,
        seat: FurnitureSeat(
            position: SIMD3(100, 0, 0), heading: 0,
            animationType: FurnitureSeat.sitAnimation, keyword: nil
        )
    )
    private static let firstAction = override(slot: 0, package: 0x120)
    private static let secondAction = override(slot: 1, package: 0x120)
    private static let walkAway = override(slot: 2, package: 0x121)

    @Test func aNextPackageThatSitsInTheSameSeatKeepsTheActorSeated() throws {
        let (coordinator, world) = try Self.seatedOnTheBlock()
        let movesBefore = world.moves.count
        // The seat's heading differs from the actor's, as at a seat with a sitting rotation.
        world.turnLeft = 1

        coordinator.clearOverride(owner: Self.firstAction.owner, actor: Self.actor)
        // A Sit procedure ends once the actor sits, so the second action is done at once.
        #expect(coordinator.runOverride(Self.secondAction, actor: Self.actor) == .done)

        #expect(!world.unseats.contains(Self.seat), "the actor must not get up")
        #expect(world.occupiedSeat == Self.seat)
        #expect(world.moves.count == movesBefore, "a seated actor walks nowhere")
        #expect(world.seatings == [Self.seat], "a seated actor is not seated again")
        #expect(coordinator.seatTurns[Self.actor] == nil, "a seated actor does not turn")
        #expect(coordinator.executions[Self.actor]?.seat == Self.seat)
        #expect(coordinator.keptSeats.isEmpty)
    }

    @Test func aNextPackageWithoutTheSeatGetsTheActorUp() throws {
        let (coordinator, world) = try Self.seatedOnTheBlock()

        coordinator.clearOverride(owner: Self.firstAction.owner, actor: Self.actor)
        #expect(!world.unseats.contains(Self.seat), "the seat waits for the next package")
        #expect(coordinator.runOverride(Self.walkAway, actor: Self.actor) == .running)

        #expect(world.unseats.last == Self.seat)
        #expect(world.occupiedSeat == nil)
        #expect(coordinator.keptSeats.isEmpty)
    }

    @Test func noNextPackageGetsTheActorUpOnTheNextPass() throws {
        let (coordinator, world) = try Self.seatedOnTheBlock()

        coordinator.clearOverride(owner: Self.firstAction.owner, actor: Self.actor)
        coordinator.advance(by: 0.1)

        #expect(world.unseats.last == Self.seat)
        #expect(coordinator.keptSeats.isEmpty)
    }

    /// The actor walked to the block under the first action and sat down there.
    private static func seatedOnTheBlock() throws -> (PackageCoordinator, FakePackageWorld) {
        let target = [Package.DataInput(index: 0, type: "PTDA", value: .target(
            Package.Target(rawKind: 0, value: 0x900, countOrDistance: 0)
        ))]
        let place = [Package.DataInput(index: 0, type: "PLDT", value: .location(
            Package.Location(rawKind: 0, value: 0x700, radius: 0)
        ))]
        let packages = try [
            PackageRuntimeFixture.package(
                id: 0x120, editorID: "ToTheBlock", procedureNames: ["Sit"], dataInputs: target
            ),
            PackageRuntimeFixture.package(
                id: 0x121, editorID: "WalkThere", procedureNames: ["Travel"], dataInputs: place
            ),
            PackageRuntimeFixture.package(id: 0x111, editorID: "Linger", procedureNames: ["Wait"])
        ]
        let actors: [UInt32: ActorBase] = try [
            0x610: PackageRuntimeFixture.actorBase(id: 0x610, packages: [0x111])
        ]
        let world = FakePackageWorld()
        world.residents = try [PackageRuntimeFixture.residentActor(0x500, base: 0x610)]
        world.targetReference = block
        world.offeredSeat = seat
        let coordinator = PackageCoordinator(
            world: world,
            data: PackageSessionData(store: PackageStore(
                packages: packages,
                actorTemplates: ActorTemplateResolver(actors: actors, leveledActors: [:])
            ), conditionFunctions: .standard)
        )
        coordinator.advance()
        #expect(coordinator.runOverride(firstAction, actor: actor) == .running)
        #expect(world.moves.last == seat.seat.root, "the first action walks to the seat")
        coordinator.movementSettled(actor: actor, reason: .arrival)
        #expect(world.seatings == [seat])
        world.occupiedSeat = seat
        return (coordinator, world)
    }

    private static func override(slot: UInt32, package: UInt32) -> PackageOverride {
        PackageOverride(
            packages: [FormID(package)],
            owner: PackageOverrideOwner(source: FormID(0x4000), slot: slot), aliasQuest: nil
        )
    }
}
