// FurnitureCoordinator: the player and packages share one set of seats; standing
// frees them, and `IsFurnitureInUse` tells a reserved seat from a used one.

@testable import OpenSkyAIPackages
import OpenSkyFormatsESM
import OpenSkyWorldInterface
import simd
import Testing

@MainActor
private final class FakeFurnitureWorld: FurnitureWorld {
    var seats: [ReferenceKey: [FurnitureSeat]] = [:]
    var positions: [ReferenceKey: SIMD3<Float>] = [:]
    var seated: [ReferenceKey: FurnitureOccupancy] = [:]
    var stoodAt: [ReferenceKey: SIMD3<Float>] = [:]
    var moved: [ReferenceKey: FurniturePose] = [:]
    var motions: [ReferenceKey: FurnitureMotionSample] = [:]
    var traits: [ReferenceKey: FurnitureActorTraits] = [:]
    var loadingExits: Set<ReferenceKey> = []
    var special: Set<ReferenceKey> = []
    var ownedByOthers: Set<ReferenceKey> = []
    var viewYaw: Float?

    func furnitureSeats(of furniture: ReferenceKey) -> [FurnitureSeat]? {
        seats[furniture]
    }

    func furnitureActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
        positions[actor]
    }

    func furnitureActorHasKeyword(_: ReferenceKey, _: FormID) -> Bool {
        false
    }

    func furnitureActorTraits(_ actor: ReferenceKey) -> FurnitureActorTraits {
        traits[actor] ?? FurnitureActorTraits()
    }

    func furnitureIsSpecial(_ furniture: ReferenceKey) -> Bool {
        special.contains(furniture)
    }

    func furnitureOwnerAllows(_ actor: ReferenceKey, _ furniture: ReferenceKey) -> Bool {
        !ownedByOthers.contains(furniture)
    }

    func placeSeated(_ actor: ReferenceKey, in occupancy: FurnitureOccupancy) {
        seated[actor] = occupancy
    }

    func placeStanding(_ actor: ReferenceKey, from _: FurnitureOccupancy) {
        seated[actor] = nil
    }

    func furnitureExitIsLoading(_ actor: ReferenceKey) -> Bool {
        loadingExits.contains(actor)
    }

    func furnitureMotion(of actor: ReferenceKey) -> FurnitureMotionSample? {
        motions[actor]
    }

    func moveFurnitureActor(_ actor: ReferenceKey, to pose: FurniturePose) {
        moved[actor] = pose
    }

    func finishStanding(_ actor: ReferenceKey, at pose: FurniturePose) {
        stoodAt[actor] = pose.root
    }

    func residentFurniture() -> [ReferenceKey] {
        Array(seats.keys)
    }

    func turnSeatedPlayerView(toYaw yaw: Float) {
        viewYaw = yaw
    }
}

@MainActor
struct FurnitureCoordinatorTests {
    let bench = ReferenceKey.plugin(name: "seat.esm", objectID: 10)
    let farChair = ReferenceKey.plugin(name: "seat.esm", objectID: 11)
    let farmer = ReferenceKey.plugin(name: "seat.esm", objectID: 2)

    /// A bench along x with two seats facing +y, entered from the front.
    private func world() -> FakeFurnitureWorld {
        let world = FakeFurnitureWorld()
        world.seats[bench] = [0, 100].map {
            FurnitureSeat(
                position: [$0, 0, 0], heading: 0, animationType: 1, keyword: nil, entryPoints: 1
            )
        }
        world.seats[farChair] = [FurnitureSeat(
            position: [0, 2000, 0], heading: 0, animationType: 1, keyword: nil, entryPoints: 1
        )]
        world.positions[.player] = [90, 30, 0]
        world.positions[farmer] = [0, 30, 0]
        return world
    }

    @Test func thePlayerTakesTheNearestFreeSeatAndStandsUpInFront() throws {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        let occupancy = try furniture.use(bench, by: .player).get()
        #expect(occupancy.seat.index == 1)
        #expect(occupancy.entry == 1)
        #expect(world.seated[.player] == occupancy)
        #expect(abs((world.viewYaw ?? 0) - .pi / 2) < 0.0001)
        #expect(furniture.use(bench, by: .player) == .failure(.alreadySeated))

        #expect(furniture.stand(.player))
        #expect(world.stoodAt[.player] == [100, FurnitureSeat.standDistance, 0])
        #expect(!furniture.isInUse(bench, marker: nil, ignoringReserved: false))
        #expect(!furniture.stand(.player))
    }

    @Test func aReservedSeatCountsOnlyUntilReservationsAreIgnored() throws {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        let reserved = try #require(furniture.reserve(in: bench, for: farmer, animation: 1))
        #expect(reserved.index == 0)
        #expect(furniture.isInUse(bench, marker: 0, ignoringReserved: false))
        #expect(!furniture.isInUse(bench, marker: 0, ignoringReserved: true))
        #expect(!furniture.isInUse(bench, marker: 1, ignoringReserved: false))

        furniture.sit(farmer, in: reserved)
        #expect(furniture.isInUse(bench, marker: nil, ignoringReserved: true))
        // The player cannot take the farmer's seat, so it gets the other one.
        world.positions[.player] = [0, 30, 0]
        #expect(try furniture.use(bench, by: .player).get().seat.index == 1)
        #expect(furniture.use(farChair, by: farmer) == .failure(.alreadySeated))
    }

    @Test func leavingAPackageBeforeSittingFreesTheReservation() throws {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        _ = try #require(furniture.reserve(in: bench, for: farmer, animation: 1))
        furniture.releaseReservations(of: farmer)
        #expect(!furniture.isInUse(bench, marker: nil, ignoringReserved: false))
    }

    @Test func theSwitchKeepsActorsStanding() throws {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        furniture.isEnabled = false
        #expect(furniture.use(bench, by: .player) == .failure(.disabled))
        let seat = try #require(furniture.reserve(in: bench, for: farmer, animation: 1))
        #expect(furniture.sit(farmer, in: seat) == nil)
        #expect(!furniture.isInUse(bench, marker: nil, ignoringReserved: false))
        #expect(world.seated.isEmpty)
    }

    @Test func sittingRotationTurnsTheSeatedViewAndEndsWithTheSeat() throws {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        _ = try furniture.use(bench, by: .player).get()
        furniture.setSittingRotation(degrees: -90)
        #expect(abs((world.viewYaw ?? 0) - .pi) < 0.0001)
        furniture.stand(.player)
        #expect(furniture.sittingRotation == 0)
    }

    @Test func theNearestFurnitureHasAFreeSeat() {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        #expect(furniture.nearestFurniture(to: farmer) == bench)
        world.seats[bench] = world.seats[bench]?.map {
            var off = $0
            off.isEnabled = false
            return off
        }
        #expect(furniture.nearestFurniture(to: farmer) == farChair)
    }

    /// A chair exit that steps 50 to the left and turns left, as `Chair_LeftExit` does.
    private static func leftExit(at fraction: Float) -> FurnitureMotionSample {
        FurnitureMotionSample(
            offset: [-50 * fraction, 0, 0], yaw: .pi / 2 * fraction,
            endOffset: [-50, 0, 0], endYaw: .pi / 2, isFinished: fraction >= 1
        )
    }

    @Test func anExitClipCarriesTheActorOutAndThenItStands() throws {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        let seat = try #require(furniture.reserve(in: bench, for: farmer, animation: 1))
        furniture.sit(farmer, in: seat)
        // The exit idle still loads: the farmer stays on the seat.
        world.loadingExits = [farmer]
        furniture.stand(farmer)
        #expect(world.moved[farmer] == FurniturePose(root: .zero, heading: 0))
        #expect(world.stoodAt[farmer] == nil)
        world.loadingExits = []
        world.motions[farmer] = Self.leftExit(at: 0.5)
        furniture.advance()
        #expect(furniture.isLeavingSeat(farmer))
        let halfway = try #require(world.moved[farmer])
        #expect(simd_distance(halfway.root, [-25, 0, 0]) < 0.001)
        #expect(abs(halfway.heading + .pi / 4) < 0.001)
        #expect(world.stoodAt[farmer] == nil)

        world.motions[farmer] = Self.leftExit(at: 1)
        furniture.advance()
        #expect(!furniture.isLeavingSeat(farmer))
        #expect(try simd_distance(#require(world.stoodAt[farmer]), [-50, 0, 0]) < 0.001)
    }

    @Test func anEntryClipStartsWhereItsMotionLeadsBackFrom() throws {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        let seat = try #require(furniture.reserve(in: bench, for: farmer, animation: 1))
        furniture.sit(farmer, in: seat)
        // `Chair_LeftEnter`: forward 50, then a left turn onto the seat.
        let enter = { (fraction: Float) in
            FurnitureMotionSample(
                offset: [0, 50 * fraction, 0], yaw: .pi / 2 * fraction,
                endOffset: [0, 50, 0], endYaw: .pi / 2, isFinished: fraction >= 1
            )
        }
        world.motions[farmer] = enter(0)
        furniture.advance()
        let start = try #require(world.moved[farmer])
        #expect(simd_distance(start.root, [-50, 0, 0]) < 0.001)
        #expect(abs(start.heading - .pi / 2) < 0.001)
        world.motions[farmer] = nil
        furniture.advance()
        #expect(world.moved[farmer] == FurniturePose(root: .zero, heading: 0))
    }

    @Test func childrenUseOnlyChildFurnitureAndOnlyDragonsUsePerches() {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        world.traits[farmer] = FurnitureActorTraits(isChild: true)
        #expect(furniture.reserve(in: bench, for: farmer, animation: 1) == nil)
        world.seats[bench] = world.seats[bench]?.map {
            var seat = $0
            seat.rules = FurnitureRules(childCanUse: true)
            return seat
        }
        #expect(furniture.reserve(in: bench, for: farmer, animation: 1) != nil)

        world.seats[farChair] = world.seats[farChair]?.map {
            var perch = $0
            perch.rules = FurnitureRules(isPerch: true)
            return perch
        }
        #expect(furniture.use(farChair, by: .player) == .failure(.noFreeSeat))
        world.traits[.player] = FurnitureActorTraits(isDragon: true)
        #expect((try? furniture.use(farChair, by: .player).get()) != nil)
    }

    @Test func greetingStandsUpOnlyAMustExitToTalkSitter() throws {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        let seat = try #require(furniture.reserve(in: bench, for: farmer, animation: 1))
        furniture.sit(farmer, in: seat)
        #expect(!furniture.greet(farmer))
        world.seats[farChair] = world.seats[farChair]?.map {
            var bed = $0
            bed.rules = FurnitureRules(mustExitToTalk: true)
            return bed
        }
        furniture.stand(farmer)
        world.positions[farmer] = [0, 2000, 0]
        _ = try furniture.use(farChair, by: farmer).get()
        #expect(furniture.greet(farmer))
        #expect(furniture.occupancies[farmer] == nil)
    }

    private static let area = SandboxSeatRequest(
        center: .zero, radius: 500, height: -100 ... 150,
        sits: true, sleeps: false, usesSpecialFurniture: false
    )

    @Test func aSandboxTakesTheNearestAllowedSeatAndNotTheSameFurnitureTwice() throws {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        let first = try #require(furniture.sandboxSeat(for: farmer, in: Self.area))
        #expect(first.furniture == bench)
        #expect(first.index == 0)
        furniture.releaseReservations(of: farmer)
        // The far chair is outside the area, so the bench was the only choice.
        #expect(furniture.sandboxSeat(for: farmer, in: Self.area) == nil)
    }

    @Test func aSandboxSkipsIgnoredSpecialAndOwnedFurniture() {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        world.special = [bench]
        #expect(furniture.sandboxSeat(for: farmer, in: Self.area) == nil)
        world.special = []
        world.ownedByOthers = [bench]
        #expect(furniture.sandboxSeat(for: farmer, in: Self.area) == nil)
        world.ownedByOthers = []
        world.seats[bench] = world.seats[bench]?.map {
            var seat = $0
            seat.rules = FurnitureRules(ignoredBySandbox: true)
            return seat
        }
        #expect(furniture.sandboxSeat(for: farmer, in: Self.area) == nil)
    }
}
