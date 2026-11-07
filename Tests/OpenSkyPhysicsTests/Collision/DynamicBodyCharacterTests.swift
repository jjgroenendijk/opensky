// A character walks through light clutter, is blocked by heavy bodies, and is
// carried by a heavy body it stands on, as the game's character controller does.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
import OpenSkyGameData
@testable import OpenSkyPhysics
import simd
import Testing

struct DynamicBodyCharacterTests {
    private static func placement(
        key: UInt64, at position: SIMD3<Float>, mass: Float, layer: UInt8
    ) -> DynamicBodyPlacement {
        let half = SIMD3<Float>(repeating: 20)
        let volume = DynamicCollisionVolume.box(halfExtents: half)
            ?? .radial(first: .zero, second: .zero, radius: 20)
        let shape = DynamicBodyColliderShape(
            transform: matrix_identity_float4x4, geometry: .box(halfExtents: half), material: nil
        )
        return DynamicBodyPlacement(
            key: .generated(key),
            reference: FormID(0x200 + UInt32(key)),
            definition: DynamicBodyDefinition(
                volumes: [volume], mass: mass, colliderShapes: [shape], collisionLayer: layer
            ),
            originPosition: position,
            orientation: .identityRotation
        )
    }

    private static let everywhere = ModelBounds(
        min: SIMD3(repeating: -1000), max: SIMD3(repeating: 1000)
    )

    @Test
    func lightClutterDoesNotBlockACharacter() {
        let cell = CellSceneLocation.interior(FormID(0x10))
        var world = DynamicBodyWorld()
        world.setCell(cell, placements: [
            Self.placement(key: 1, at: SIMD3(0, 0, 20), mass: 5, layer: 4),
            Self.placement(key: 2, at: SIMD3(100, 0, 20), mass: 120, layer: 4),
            Self.placement(key: 3, at: SIMD3(200, 0, 20), mass: 5, layer: 10)
        ])
        let blocking = Set(world.characterShapes(overlapping: Self.everywhere).map(\.reference))
        #expect(blocking == [FormID(0x202), FormID(0x203)])
        #expect(world.placedShapes(overlapping: Self.everywhere).count == 3, "rays still hit all")
    }

    @Test
    func aHeavyMovingBodyCarriesTheCharacterOnIt() throws {
        let cell = CellSceneLocation.interior(FormID(0x10))
        var world = DynamicBodyWorld()
        world.setCell(cell, placements: [
            Self.placement(key: 1, at: SIMD3(0, 0, 20), mass: 200, layer: 4),
            Self.placement(key: 2, at: SIMD3(300, 0, 20), mass: 5, layer: 10)
        ])
        let platform = try #require(world.bodies.firstIndex { $0.key == .generated(1) })
        world.bodies[platform].linearVelocity = SIMD3(50, 0, 0)
        let prop = try #require(world.bodies.firstIndex { $0.key == .generated(2) })
        world.bodies[prop].linearVelocity = SIMD3(-50, 0, 0)
        let capsule = PlayerCapsule.standard
        let onTop = world.characterCarry(capsule: capsule, feetPosition: SIMD3(0, 0, 40.5))
        #expect(simd_distance(onTop, SIMD3(50, 0, 0)) < 0.01, "carried at \(onTop)")
        let beside = world.characterCarry(
            capsule: capsule, feetPosition: SIMD3(300 - 20 - capsule.radius - 1, 0, 0)
        )
        #expect(beside == .zero, "a prop only blocks")
        let away = world.characterCarry(capsule: capsule, feetPosition: SIMD3(0, 400, 0))
        #expect(away == .zero)
    }
}
