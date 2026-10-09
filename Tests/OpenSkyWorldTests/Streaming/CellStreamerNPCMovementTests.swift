// A listener that starts the next move when a walk ends, as a patrol does, keeps
// that move: the streamer delivers the rest write after the runtime stores its state.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyPhysics
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
@testable import OpenSkyWorldState
import simd
import Testing

@MainActor
struct CellStreamerNPCMovementTests {
    private static let actor = ReferenceKey.plugin(name: "test.esm", objectID: 0x9000)

    @Test
    func aMoveStartedOnArrivalKeepsWalking() throws {
        let streamer = try Self.streamerWithWalker()
        var arrivals = 0
        streamer.onNPCMovementPersist = { [weak streamer] persistence in
            guard persistence.reason == .arrival else { return }
            arrivals += 1
            if arrivals == 1 {
                #expect(streamer?.moveActor(Self.actor, to: SIMD3(150, 150, 0)) == .started)
            }
        }
        #expect(streamer.moveActor(Self.actor, to: SIMD3(150, 30, 0)) == .started)

        for _ in 0 ..< 1200 where arrivals < 2 {
            streamer.advanceNPCMovement(frameTime: 1.0 / 60)
        }

        #expect(arrivals == 2, "\(streamer.npcMovementReadouts())")
        let feet = try #require(streamer.npcMovementReadouts().first?.feetPosition)
        #expect(simd_distance(SIMD2(feet.x, feet.y), SIMD2(150, 150)) < 20)
    }

    private static func streamerWithWalker() throws -> CellStreamer {
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerFixture.makeStreamer(runner: runner, radius: 0)
        let cell = CellStreamerFixture.coordinate(0, 0)
        let camera = CellGridManager.cellCenter(of: cell)
        let walker = try RuntimeReferenceEntry(
            key: actor, formID: FormID(0x9000), isPersistent: false,
            record: .actor(placedActor(position: SIMD3(30, 30, 0)))
        )
        let halfExtents = SIMD3<Float>(200, 200, 5)
        let center = SIMD3<Float>(100, 100, -5)
        let floor = StaticCollisionShape(
            reference: FormID(0x100), transform: MatrixMath.translation(center),
            geometry: .box(halfExtents: halfExtents),
            bounds: ModelBounds(min: center - halfExtents, max: center + halfExtents)
        )
        streamer.update(cameraPosition: camera)
        try runner.complete(cell, with: .success(CellStreamerFixture.cellScene(
            location: .exterior(cell),
            staticCollision: CellStreamerFixture.collisionSet(shapes: [floor]),
            references: RuntimeReferenceIndex(entries: [walker]),
            navmeshes: [NavigationRuntimeFixture.grid(id: 0x100, columns: 20, rows: 20)]
        )))
        streamer.update(cameraPosition: camera)
        return streamer
    }
}
