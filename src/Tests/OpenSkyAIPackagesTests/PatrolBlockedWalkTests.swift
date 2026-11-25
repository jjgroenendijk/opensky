// A blocked patrol walk does not end the patrol: it asks again for a walk to the same
// point, so a horse stuck behind a cart waits there instead of riding back to the start.
// A point counts as reached inside its Patrol Radius plus a margin.

@testable import OpenSkyAIPackages
@testable import OpenSkyFormatsESM
import OpenSkyWorldInterface
import simd
import Testing

struct PatrolBlockedWalkTests {
    private static func patrol() -> PackageProcedureMachine {
        PackageProcedureMachine(
            kind: .patrol, center: .zero, destination: SIMD3(100, 0, 0), radius: 0,
            path: [SIMD3(200, 0, 0), SIMD3(300, 0, 0)], seed: 1
        )
    }

    @Test func aBlockedWalkWalksToTheSamePointAgain() {
        var machine = Self.patrol()
        _ = machine.start()
        #expect(machine.handle(.arrived) == [.move(to: SIMD3(200, 0, 0))])
        #expect(machine.handle(.movementFailed).isEmpty)
        #expect(!machine.isFinished)
        #expect(machine.handle(.tick(1.0 / 60)) == [.move(to: SIMD3(200, 0, 0))])
        #expect(machine.state == .moving)
        #expect(machine.handle(.arrived) == [.move(to: SIMD3(300, 0, 0))])
    }

    @Test func aBlockedFirstWalkKeepsTheFirstPoint() {
        var machine = Self.patrol()
        _ = machine.start()
        _ = machine.handle(.movementFailed)
        #expect(machine.handle(.tick(0.1)) == [.move(to: SIMD3(100, 0, 0))])
    }

    @Test func aBlockedTravelStillFails() {
        var machine = PackageProcedureMachine(
            kind: .travel, center: SIMD3(100, 0, 0), radius: 0, seed: 1
        )
        _ = machine.start()
        _ = machine.handle(.movementFailed)
        #expect(machine.state == .failed)
    }
}

@MainActor
struct PatrolPointArrivalTests {
    @Test func aPatrolPointIsReachedFiftyUnitsShortOfIt() {
        var machine = PackageProcedureMachine(
            kind: .patrol, center: .zero, destination: SIMD3(100, 0, 0), radius: 0,
            path: [SIMD3(200, 0, 0)], seed: 1
        )
        _ = machine.start()
        #expect(machine.hasReachedArea(SIMD3(51, 0, 170)))
        #expect(!machine.hasReachedArea(SIMD3(49, 0, 0)))
        #expect(!machine.hasReachedArea(SIMD3(100, 0, 200)))
        _ = machine.handle(.arrived)
        #expect(machine.hasReachedArea(SIMD3(160, 0, 0)))
        #expect(!machine.hasReachedArea(SIMD3(100, 0, 0)))
    }
}

/// A resolver whose patrol path is two points and whose other answers are empty.
@MainActor
private struct PatrolResolver: PackageInputResolving {
    func place(of _: Package.Location) -> PackagePlace? {
        nil
    }

    func reference(of _: Package.Target) -> ReferenceKey? {
        nil
    }

    func position(of _: ReferenceKey) -> SIMD3<Float>? {
        nil
    }

    func patrolPath(from _: Package.Target) -> [SIMD3<Float>]? {
        [SIMD3(10, 0, 0), SIMD3(20, 0, 0)]
    }

    func seat(in _: ReferenceKey, animation _: UInt16) -> PackageSeat? {
        nil
    }
}

@MainActor
struct PatrolRadiusInputTests {
    private static func setup(radius: Package.DataValue) -> PackageLeafSetup {
        PackageProcedureInputs(
            leaf: PackageProcedureLeaf(node: 0, kind: .patrol, inputIndexes: [0, 1, 2, 3, 4, 5]),
            values: [
                0: .target(Package.Target(rawKind: 0, value: 0x701, countOrDistance: 0)),
                1: radius
            ],
            objectLists: [:], start: .zero, seed: 1
        ).build(resolver: PatrolResolver())
    }

    /// The Patrol Radius input widens each point's arrival area; a negative one is 0.
    @Test func thePatrolRadiusInputSetsTheArrivalRadius() {
        #expect(Self.setup(radius: .float(64)).setup.radius == 64)
        #expect(Self.setup(radius: .float(-5)).setup.radius == 0)
    }
}
