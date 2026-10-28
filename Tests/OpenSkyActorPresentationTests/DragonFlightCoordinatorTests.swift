// The free-flight shell: which dragons fly, forced orders, touchdown events, perches,
// the forced landings, and the actors that leave in the air.

@testable import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsESM
import simd
import Testing

@MainActor
private final class FakeDragonFlightWorld: DragonFlightWorld {
    let dragonFlightSettings = DragonFlightSettings.standard
    var candidates: [DragonFlightCandidate] = []
    var held: [ReferenceKey] = []
    var released: [ReferenceKey] = []
    var raised: [String] = []
    var dust: [SIMD3<Float>] = []
    var lastMove: DragonFlightState?
    var perches: [DragonPerch] = []
    /// What the landing idle tree answers for a perch, keyed by nil for no perch.
    var treeEvents: [ReferenceKey?: String] = [:]

    func dragonFlightCandidates() -> [DragonFlightCandidate] {
        candidates
    }

    func dragonPerches() -> [DragonPerch] {
        perches
    }

    func landingEvent(for _: ReferenceKey, perch: ReferenceKey?) -> String? {
        treeEvents[perch]
    }

    func holdForFlight(_ actor: ReferenceKey) -> (feet: SIMD3<Float>, yaw: Float)? {
        held.append(actor)
        return candidates.first { $0.key == actor }.map { ($0.feet, $0.yaw) }
    }

    func moveFlying(
        _: ReferenceKey, state: DragonFlightState,
        inputs _: [(name: String, value: BehaviorVariableValue)]
    ) {
        lastMove = state
    }

    func releaseFromFlight(_ actor: ReferenceKey) {
        released.append(actor)
    }

    func flightGroundHeight(at _: SIMD2<Float>) -> Float? {
        0
    }

    func raiseFlightEvent(_ name: String, on _: ReferenceKey) {
        raised.append(name)
    }

    func playLandingDust(_: ReferenceKey, at point: SIMD3<Float>) {
        dust.append(point)
    }
}

@MainActor
struct DragonFlightCoordinatorTests {
    private static let dragon = ReferenceKey.generated(7)

    private func setUp(
        _ change: (inout DragonFlightCandidate) -> Void = { _ in }
    ) -> (DragonFlightCoordinator, FakeDragonFlightWorld) {
        let world = FakeDragonFlightWorld()
        var candidate = DragonFlightCandidate(key: Self.dragon, feet: SIMD3(0, 0, 0), yaw: 0)
        change(&candidate)
        world.candidates = [candidate]
        return (DragonFlightCoordinator(world: world), world)
    }

    private func tick(_ flight: DragonFlightCoordinator, seconds: Float) {
        for _ in 0 ..< Int(seconds * 30) {
            flight.tick(deltaTime: 1.0 / 30)
        }
    }

    @Test func anAirFightTakesOffAndCirclesTheTarget() {
        let (flight, world) = setUp {
            $0.fight = .air
            $0.target = SIMD3(1000, 0, 0)
        }
        flight.tick(deltaTime: 1.0 / 30)
        #expect(world.held == [Self.dragon])
        #expect(world.raised == ["TakeOff"])
        #expect(flight.phase(of: Self.dragon) == .takingOff)
        #expect(flight.flyingActors == [Self.dragon])
        tick(flight, seconds: 6)
        #expect(flight.phase(of: Self.dragon) == .cruising)
    }

    @Test func aFightOnTheGroundOrNoFightKeepsItDown() {
        let (flight, world) = setUp { $0.fight = .ground }
        tick(flight, seconds: 1)
        #expect(world.held.isEmpty)
        #expect(flight.flyingActors.isEmpty)
    }

    @Test func indoorsOrForbiddenByAScriptNoDragonFlies() {
        let changes: [(inout DragonFlightCandidate) -> Void] = [
            { $0.canFlyHere = false }, { $0.isAllowedToFly = false }, { $0.isRidden = true }
        ]
        for change in changes {
            let (flight, world) = setUp {
                $0.fight = .air
                $0.target = SIMD3(1000, 0, 0)
                change(&$0)
            }
            tick(flight, seconds: 1)
            #expect(world.held.isEmpty)
        }
    }

    @Test func aForcedLandingBringsItDownAndEndsTheOrder() {
        let (flight, world) = setUp()
        flight.order(.takeOff, for: Self.dragon)
        tick(flight, seconds: 8)
        #expect(flight.phase(of: Self.dragon) == .cruising)
        flight.order(.land, for: Self.dragon)
        tick(flight, seconds: 40)
        #expect(world.raised.contains("FlyStopDefault"))
        #expect(world.released == [Self.dragon])
        #expect(flight.phase(of: Self.dragon) == .grounded)
        #expect(flight.orders[Self.dragon] == nil)
    }

    @Test func clipEventsPlayDustAndTouchDown() {
        let (flight, world) = setUp()
        #expect(flight.handle("FlightLandingEffect", from: Self.dragon))
        #expect(!flight.handle("WingFlapLeft", from: Self.dragon))
        flight.order(.takeOff, for: Self.dragon)
        tick(flight, seconds: 8)
        flight.order(.land, for: Self.dragon)
        flight.tick(deltaTime: 1.0 / 30)
        #expect(flight.phase(of: Self.dragon) == .landing)
        flight.handle("flightlandingeffect", from: Self.dragon)
        #expect(world.dust.count == 1 && world.dust.first?.z == 0)
        flight.handle("FlightForcefulLandStart", from: Self.dragon)
        #expect(world.released == [Self.dragon])
        #expect(world.lastMove?.feet.z == 0)
        #expect(flight.phase(of: Self.dragon) == .grounded)
    }

    @Test func anActorThatLeavesInTheAirDropsToTheGround() {
        let (flight, world) = setUp()
        flight.order(.takeOff, for: Self.dragon)
        tick(flight, seconds: 6)
        world.candidates = []
        flight.tick(deltaTime: 1.0 / 30)
        #expect(world.released == [Self.dragon])
        #expect(world.lastMove?.feet.z == 0)
        #expect(flight.flyingActors.isEmpty)
    }

    private static let tower = DragonPerch(
        reference: .generated(40), feet: SIMD3(2000, 0, 900), yaw: .pi
    )

    @Test func aPerchStageLandsOnAPerchFacingTheTargetAndLeavesForTheAir() {
        let (flight, world) = setUp {
            $0.fight = .air
            $0.target = SIMD3(0, 0, 0)
        }
        world.perches = [Self.tower]
        world.treeEvents = [Self.tower.reference: "FlyStopPerchTower"]
        tick(flight, seconds: 8)
        world.candidates[0].fight = .perch
        tick(flight, seconds: 60)
        #expect(flight.phase(of: Self.dragon) == .perched)
        #expect(world.raised.contains("FlyStopPerchTower"))
        #expect(world.lastMove?.feet == Self.tower.feet)
        #expect(flight.flights[Self.dragon]?.yaw == Self.tower.yaw)
        world.raised = []
        world.candidates[0].fight = .air
        flight.tick(deltaTime: 1.0 / 30)
        #expect(world.raised == ["TakeOff"])
        #expect(flight.phase(of: Self.dragon) == .takingOff)
    }

    @Test func aPerchStageWithoutAPerchInReachHovers() {
        let (flight, world) = setUp {
            $0.fight = .air
            $0.target = SIMD3(0, 0, 0)
        }
        world.perches = [DragonPerch(reference: .generated(41), feet: SIMD3(9000, 0, 0), yaw: .pi)]
        tick(flight, seconds: 8)
        world.candidates[0].fight = .perch
        tick(flight, seconds: 4)
        #expect(flight.phase(of: Self.dragon) == .hovering)
    }

    @Test func dragonrendAsksForAHastyLandingAtOnce() {
        let (flight, world) = setUp {
            $0.fight = .air
            $0.target = SIMD3(1000, 0, 0)
        }
        tick(flight, seconds: 8)
        world.candidates[0].isRended = true
        flight.tick(deltaTime: 1.0 / 30)
        #expect(flight.landingRequests == [Self.dragon: .hasty])
        #expect(flight.flights[Self.dragon]?.isApproaching == true)
        #expect(world.raised.last == "FlyStopHasty")
        #expect(flight.landingEvents[Self.dragon] == "FlyStopHasty")
        tick(flight, seconds: 40)
        #expect(flight.phase(of: Self.dragon) == .grounded)
        #expect(flight.landingRequests.isEmpty)
    }

    @Test func aDragonThatDiesInTheAirCrashLands() {
        let (flight, world) = setUp()
        world.treeEvents = [nil: "FlyStopCrash"]
        flight.order(.takeOff, for: Self.dragon)
        tick(flight, seconds: 8)
        world.candidates[0].isDead = true
        flight.tick(deltaTime: 1.0 / 30)
        #expect(flight.landingRequests == [Self.dragon: .crash])
        #expect(world.raised.last == "FlyStopCrash")
        tick(flight, seconds: 40)
        #expect(world.released == [Self.dragon])
        #expect(flight.flyingActors.isEmpty)
    }

    @Test func anInjuredDragonLandsBesideItsTarget() {
        let (flight, world) = setUp {
            $0.fight = .air
            $0.target = SIMD3(1000, 0, 0)
        }
        tick(flight, seconds: 8)
        world.candidates[0].isInjured = true
        tick(flight, seconds: 40)
        #expect(world.raised.contains("FlyStopDefault"))
        #expect(flight.phase(of: Self.dragon) == .grounded)
    }

    @Test func aDeadDragonOnTheGroundDoesNotTakeOff() {
        let (flight, world) = setUp {
            $0.isDead = true
            $0.fight = .air
            $0.target = SIMD3(1000, 0, 0)
        }
        tick(flight, seconds: 1)
        #expect(world.held.isEmpty)
    }
}
