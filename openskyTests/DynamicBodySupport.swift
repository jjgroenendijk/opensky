// Shared scene builders for the dynamic rigid-body suites (issue #193).
// Everything here is synthetic: a floor, a wall, and boxes described in code.
// No game asset is read and none could be — the solver's inputs are engine
// values, not NIF bytes.

@testable import opensky
import simd

enum DynamicBodyScene {
    /// A floor quad centred on the origin, `extent` units to each side.
    static func floor(z: Float = 0, extent: Float = 400) -> StaticCollisionShape {
        quad(
            SIMD3(-extent, -extent, z), SIMD3(extent, -extent, z),
            SIMD3(extent, extent, z), SIMD3(-extent, extent, z)
        )
    }

    /// A wall in the plane `x == at`, facing back along -x.
    static func wall(at x: Float, extent: Float = 400) -> StaticCollisionShape {
        quad(
            SIMD3(x, -extent, -extent), SIMD3(x, extent, -extent),
            SIMD3(x, extent, extent), SIMD3(x, -extent, extent)
        )
    }

    static func quad(
        _ first: SIMD3<Float>,
        _ second: SIMD3<Float>,
        _ third: SIMD3<Float>,
        _ fourth: SIMD3<Float>,
        reference: FormID = FormID(1)
    ) -> StaticCollisionShape {
        let vertices = [first, second, third, fourth]
        // ModelBounds.containing never returns nil for four points, but the
        // no-force-unwrap rule holds in tests too.
        let bounds = ModelBounds.containing(vertices)
            ?? ModelBounds(min: .zero, max: .zero)
        return StaticCollisionShape(
            reference: reference,
            transform: matrix_identity_float4x4,
            geometry: .triangleSoup(vertices: vertices, indices: [0, 1, 2, 0, 2, 3]),
            bounds: bounds
        )
    }

    static func query(_ shapes: [StaticCollisionShape]) -> (ModelBounds) -> [StaticCollisionShape] {
        { bounds in shapes.filter { $0.bounds.overlaps(bounds) } }
    }

    /// A cube body of half-extent `half`, centred at `center`.
    static func cube(
        key: ReferenceKey,
        center: SIMD3<Float>,
        half: Float = 10,
        mass: Float = 20,
        orientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 0, 1))
    ) -> DynamicBody {
        let volume = DynamicCollisionVolume.box(halfExtents: SIMD3(repeating: half))
            ?? .radial(first: .zero, second: .zero, radius: half)
        return DynamicBody(
            key: key,
            reference: FormID(0x100),
            cell: .interior(FormID(0x10)),
            definition: DynamicBodyDefinition(volumes: [volume], mass: mass),
            originPosition: center,
            orientation: orientation
        )
    }

    /// Runs `count` fixed steps against `world`.
    @discardableResult
    static func run(
        bodies: inout [DynamicBody],
        world: DynamicStepWorld,
        steps: Int
    ) -> DynamicStepStats {
        var stats = DynamicStepStats()
        for _ in 0 ..< steps {
            stats = DynamicBodySolver.step(
                bodies: &bodies, world: world, dt: WalkController.fixedTimeStep
            )
        }
        return stats
    }
}
