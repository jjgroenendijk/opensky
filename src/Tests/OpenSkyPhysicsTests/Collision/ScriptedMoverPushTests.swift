// A box a script moves shoves the loose bodies it touches. Synthetic bodies only.

import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyPhysics
import simd
import Testing

struct ScriptedMoverPushTests {
    private static let cell = CellSceneLocation.interior(FormID(0x10))

    private static func world(bodyAt point: SIMD3<Float>) -> DynamicBodyWorld {
        var world = DynamicBodyWorld()
        world.add(DynamicBodyPlacement(
            key: .generated(1), reference: FormID(0x300),
            definition: RagdollFixture.bone(center: point).definition,
            originPosition: point, orientation: .identityRotation
        ), in: cell)
        return world
    }

    private static func mover(at position: SIMD3<Float>) -> ScriptedMover {
        var placement = matrix_identity_float4x4
        placement.columns.3 = SIMD4(position, 1)
        return ScriptedMover(
            placement: placement, minimum: SIMD3(-50, -50, 0), maximum: SIMD3(50, 50, 10),
            velocity: SIMD3(0, 0, 40)
        )
    }

    @Test func aRisingPlatformLiftsTheBodyOnIt() {
        var world = Self.world(bodyAt: SIMD3(10, 0, 12))
        let pushed = world.push(by: Self.mover(at: .zero))
        #expect(pushed == 1)
        let lift = world.body(for: .generated(1))?.linearVelocity.z ?? 0
        #expect(abs(lift - 40) < 0.01)
        let again = world.push(by: Self.mover(at: .zero))
        #expect(again == 0)
    }

    @Test func aBodyOutsideTheBoxStaysStill() {
        var world = Self.world(bodyAt: SIMD3(200, 0, 12))
        let pushed = world.push(by: Self.mover(at: .zero))
        #expect(pushed == 0)
        #expect(world.body(for: .generated(1))?.linearVelocity == .zero)
    }
}
