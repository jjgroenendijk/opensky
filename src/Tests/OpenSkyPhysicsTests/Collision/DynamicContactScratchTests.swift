// The static contact buffers a world keeps across bodies and steps give the same
// bodies as fresh buffers on every step.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyPhysics
import simd
import Testing

struct DynamicContactScratchTests {
    @Test
    func keptBuffersStepTheSameBodiesAsFreshOnes() {
        let shapes = [
            DynamicBodyScene.floor(),
            DynamicBodyScene.box(center: SIMD3(30, 0, 10), half: SIMD3(20, 20, 10)),
            DynamicBodyScene.wall(at: 80)
        ]
        let world = DynamicStepWorld(staticCandidates: DynamicBodyScene.query(shapes))
        let tilt = simd_quatf(angle: 0.4, axis: simd_normalize(SIMD3(1, 1, 0)))
        let start = [
            DynamicBodyScene.cube(key: .generated(1), center: SIMD3(30, 0, 60), orientation: tilt),
            DynamicBodyScene.cube(key: .generated(2), center: SIMD3(-20, 5, 40), half: 6),
            DynamicBodyScene.cube(key: .generated(3), center: SIMD3(70, -10, 30), half: 4)
        ]
        var fresh = start
        var kept = start
        var scratch = DynamicContactScratch()
        for _ in 0 ..< 240 {
            DynamicBodySolver.step(bodies: &fresh, world: world, dt: PhysicsStep.fixedTimeStep)
            DynamicBodySolver.step(
                bodies: &kept, world: world, dt: PhysicsStep.fixedTimeStep, scratch: &scratch
            )
        }

        #expect(kept.map(\.position) == fresh.map(\.position))
        #expect(kept.map(\.orientation.vector) == fresh.map(\.orientation.vector))
        #expect(fresh.allSatisfy { $0.position.z > 0 })
    }
}
