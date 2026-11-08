// A top-heavy body on a small base stands still: the vanilla glazed goblet is a
// wide cup on a narrow foot, and it once tipped over on the shelf it stood on.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyPhysics
import simd
import Testing

struct DynamicBodyRestingTests {
    /// The goblet's collider as the cell build gives it: a foot 3 by 3.4 units under
    /// a cup 6.2 units wide, around a centre of mass a little off the axis.
    private static func goblet(at foot: SIMD3<Float>) throws -> DynamicBody {
        let offset = SIMD3<Float>(0.088, 0, 0)
        let footBox = try #require(DynamicCollisionVolume.box(
            halfExtents: SIMD3(1.5, 1.7, 2.3), center: SIMD3(0, 0, -3.7) + offset
        ))
        let cup = try #require(DynamicCollisionVolume.box(
            halfExtents: SIMD3(3.1, 3.1, 1.9), center: SIMD3(0, 0, 3.7) + offset
        ))
        return DynamicBody(
            key: .generated(1), reference: FormID(0x100), cell: .interior(FormID(0x10)),
            definition: DynamicBodyDefinition(volumes: [footBox, cup], mass: 0.5),
            originPosition: foot + SIMD3(0, 0, 6.0),
            orientation: .identityRotation
        )
    }

    @Test
    func aGobletStandsOnItsFoot() throws {
        let world = DynamicStepWorld(
            staticCandidates: DynamicBodyScene.query([DynamicBodyScene.floor()])
        )
        var bodies = try [Self.goblet(at: SIMD3(0, 0, 0.3))]
        DynamicBodyScene.run(bodies: &bodies, world: world, steps: 600)
        let body = bodies[0]
        let up = body.orientation.act(SIMD3(0, 0, 1))
        #expect(up.z > 0.999, "the goblet tipped to \(up)")
        #expect(abs(body.position.z - 6) < 1.5, "the goblet ended at \(body.position)")
        #expect(body.isSleeping, "the goblet never came to rest")
    }
}
