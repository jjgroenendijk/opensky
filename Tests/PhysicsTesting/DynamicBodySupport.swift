// Synthetic collision scenes for the physics, capsule, and camera suites: a
// floor, walls, boxes, and the queries over them, all built in code.

@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
import simd

public enum DynamicBodyScene {
    /// A floor quad centred on the origin, `extent` units to each side.
    public static func floor(
        z: Float = 0,
        extent: Float = 400,
        material: FormID? = nil
    ) -> StaticCollisionShape {
        quad(
            SIMD3(-extent, -extent, z), SIMD3(extent, -extent, z),
            SIMD3(extent, extent, z), SIMD3(-extent, extent, z),
            material: material
        )
    }

    /// A wall in the plane `x == at`, facing back along -x.
    public static func wall(at x: Float, extent: Float = 400) -> StaticCollisionShape {
        quad(
            SIMD3(x, -extent, -extent), SIMD3(x, -extent, extent),
            SIMD3(x, extent, extent), SIMD3(x, extent, -extent)
        )
    }

    /// A one-sided quad: the narrowphase reads the normal off the winding, so
    /// `first -> second -> third` runs counter-clockwise seen from the front.
    public static func quad(
        _ first: SIMD3<Float>,
        _ second: SIMD3<Float>,
        _ third: SIMD3<Float>,
        _ fourth: SIMD3<Float>,
        reference: FormID = FormID(1),
        material: FormID? = nil
    ) -> StaticCollisionShape {
        let vertices = [first, second, third, fourth]
        let bounds = ModelBounds.containing(vertices)
            ?? ModelBounds(min: .zero, max: .zero)
        return StaticCollisionShape(
            reference: reference,
            transform: matrix_identity_float4x4,
            geometry: .triangleSoup(vertices: vertices, indices: [0, 1, 2, 0, 2, 3]),
            bounds: bounds,
            material: material
        )
    }

    /// An axis-aligned static box of half-extent `half`, centred at `center`.
    public static func box(
        center: SIMD3<Float>,
        half: SIMD3<Float>,
        reference: FormID = FormID(2)
    ) -> StaticCollisionShape {
        StaticCollisionShape(
            reference: reference,
            transform: MatrixMath.translation(center),
            geometry: .box(halfExtents: half),
            bounds: ModelBounds(min: center - half, max: center + half)
        )
    }

    /// The candidate query of a `StaticCollisionSet` over `shapes`, as a
    /// streamed cell hands it to the player controller.
    public static func candidateQuery(_ shapes: [StaticCollisionShape])
        -> (ModelBounds) -> [StaticCollisionShape]
    {
        StaticCollisionSet(location: nil, shapes: shapes, stats: StaticCollisionStats())
            .candidates
    }

    public static func query(_ shapes: [StaticCollisionShape])
        -> (ModelBounds) -> [StaticCollisionShape]
    {
        { bounds in shapes.filter { $0.bounds.overlaps(bounds) } }
    }

    /// A cube body of half-extent `half`, centred at `center`.
    public static func cube(
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
    public static func run(
        bodies: inout [DynamicBody],
        world: DynamicStepWorld,
        steps: Int
    ) -> DynamicStepStats {
        var stats = DynamicStepStats()
        for _ in 0 ..< steps {
            stats = DynamicBodySolver.step(
                bodies: &bodies, world: world, dt: PhysicsStep.fixedTimeStep
            )
        }
        return stats
    }
}
