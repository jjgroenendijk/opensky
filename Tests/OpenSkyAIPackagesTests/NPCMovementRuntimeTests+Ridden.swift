// A mount the player rides: the player's drive moves it, packages cannot, and its
// release parks and persists it where the player left it.

@testable import OpenSkyAIPackages
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
@testable import OpenSkyWorldState
import simd
import Testing

extension NPCMovementRuntimeTests {
    @Test
    func aRiddenActorMovesOnlyWhereThePlayerSteersIt() {
        var runtime = NPCMovementRuntime()
        var persistence: [NPCMovementPersistence] = []
        runtime.onPersist = { persistence.append($0) }
        let hold = runtime.takeRidden(Self.face(actor: actor, target: .zero))
        #expect(hold.feetPosition == .zero)
        #expect(runtime.isRidden(actor))
        let walked = runtime.start(Self.start(
            actor: actor,
            path: Self.path(waypoints: [SIMD3(200, 0, 0)], target: SIMD3(200, 0, 0))
        ))
        #expect(!walked)
        runtime.face(Self.face(actor: actor, target: SIMD3(0, 200, 0)))
        #expect(runtime.activeFacingCount == 0)

        let first = CellSceneLocation.exterior(CellCoordinate(x: 0, y: 0))
        let second = CellSceneLocation.exterior(CellCoordinate(x: 1, y: 0))
        runtime.steerRidden(actor, to: SIMD3(50, 0, 0), yaw: 1, cell: first)
        runtime.steerRidden(actor, to: SIMD3(5000, 0, 0), yaw: 1, cell: second)
        #expect(persistence.map(\.reason) == [.cellHandoff])
        #expect(runtime.transform(for: actor)?.position == SIMD3(5000, 0, 0))
        #expect(runtime.readouts().first?.state == .ridden)
        #expect(runtime.instanceDeltas()[UInt32(1)] != nil)

        let released = runtime.releaseRidden(actor)
        #expect(released)
        #expect(!runtime.isRidden(actor))
        #expect(persistence.last?.reason == .halt)
        #expect(runtime.transform(for: actor)?.position == SIMD3(5000, 0, 0))
        #expect(abs((runtime.readouts().first?.yaw ?? 0) - 1) < 0.0001)
    }
}
