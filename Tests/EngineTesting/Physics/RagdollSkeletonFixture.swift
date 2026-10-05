// A decoded skeleton built in code for the ragdoll build. Shared by
// `RagdollDefinitionTests` and `RagdollSelfCollisionTests`, which differ only
// in their `HavokFilter`s, so filters are a parameter.

@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import simd

public enum RagdollSkeletonFixture {
    /// Bones a spacing apart along x, each with a capsule body centred on its
    /// bone, consecutive pairs joined by a ragdoll cone at the midpoint.
    public static let spacing: Float = 30

    /// The block index the body for bone `index` answers to. The joint blocks
    /// are derived from these, so a test asserting on a reported skip can name
    /// the block it expects.
    public static func block(of index: Int) -> Int {
        100 + index
    }

    public static func bindMatrices(count: Int) -> [float4x4] {
        (0 ..< count).map { MatrixMath.translation(SIMD3(Float($0) * spacing, 0, 0)) }
    }

    /// One body per bone and a cone joint at each midpoint. Pivots are in each
    /// body's entity space, as a NIF writes them: `+spacing/2` and `-spacing/2`.
    /// A name past the end of `filters` gets the inert static filter.
    public static func model(
        boneNames: [String],
        filters: [NIFCollisionFilter] = []
    ) -> NIFCollisionModel {
        var bodies: [NIFCollisionBody] = []
        for (index, name) in boneNames.enumerated() {
            let block = block(of: index)
            var constraints: [NIFCollisionConstraint] = []
            if index > 0 {
                constraints.append(cone(entityA: block - 1, entityB: block))
            }
            if index + 1 < boneNames.count {
                constraints.append(cone(entityA: block, entityB: block + 1))
            }
            bodies.append(body(
                name: name,
                block: block,
                index: index,
                constraints: constraints,
                filter: filters.indices.contains(index)
                    ? filters[index]
                    : NIFCollisionFilter(layer: 1, flags: 0, group: 0)
            ))
        }
        return NIFCollisionModel(
            bodies: bodies, unsupportedReachableBlocks: [:], decodeFailures: []
        )
    }

    private static func body(
        name: String,
        block: Int,
        index: Int,
        constraints: [NIFCollisionConstraint],
        filter: NIFCollisionFilter
    ) -> NIFCollisionBody {
        NIFCollisionBody(
            targetBlock: Int32(block),
            targetName: name,
            bodyBlock: block,
            carrier: .blendCollisionObject,
            collisionObjectFlags: 0,
            worldFilter: filter,
            rigidBodyFilter: filter,
            entityResponse: 1,
            rigidBodyResponse: 1,
            dynamics: dynamics,
            constraints: constraints,
            bodyFlags: 0,
            transform: MatrixMath.translation(SIMD3(Float(index) * spacing, 0, 0)),
            shapes: [NIFCollisionShape(
                transform: matrix_identity_float4x4,
                geometry: .sphere(radius: 6)
            )]
        )
    }

    private static var dynamics: NIFRigidBodyDynamics {
        NIFRigidBodyDynamics(
            mass: 8,
            inertiaTensor: matrix_identity_float3x3,
            centerOfMass: .zero,
            linearVelocity: .zero,
            angularVelocity: .zero,
            linearDamping: 0.1,
            angularDamping: 0.05,
            timeFactor: 1,
            gravityFactor: 1,
            friction: 0.5,
            rollingFrictionMultiplier: 0,
            restitution: 0.3,
            maxLinearVelocity: 100,
            maxAngularVelocity: 30,
            penetrationDepth: 0,
            rawMotionSystem: NIFMotionSystem.boxInertia.rawValue,
            rawDeactivatorType: 0,
            rawSolverDeactivation: 0,
            rawQualityType: 0
        )
    }

    /// The block index the cone between two bodies answers to.
    public static func coneBlock(entityA: Int, entityB: Int) -> Int {
        entityA * 1000 + entityB
    }

    private static func cone(entityA: Int, entityB: Int) -> NIFCollisionConstraint {
        NIFCollisionConstraint(
            block: coneBlock(entityA: entityA, entityB: entityB),
            entityA: Int32(entityA),
            entityB: Int32(entityB),
            priority: 1,
            data: .ragdoll(NIFRagdollConstraint(
                frameA: frame(pivot: SIMD3(spacing / 2, 0, 0)),
                frameB: frame(pivot: SIMD3(-spacing / 2, 0, 0)),
                coneMaxAngle: 0.5,
                planeMinAngle: -0.4,
                planeMaxAngle: 0.4,
                twistMinAngle: -0.3,
                twistMaxAngle: 0.3,
                maxFriction: 10,
                motor: .none
            ))
        )
    }

    private static func frame(pivot: SIMD3<Float>) -> NIFConstraintRagdollFrame {
        NIFConstraintRagdollFrame(
            twist: SIMD3(1, 0, 0),
            plane: SIMD3(0, 0, 1),
            motor: SIMD3(0, 1, 0),
            pivot: pivot
        )
    }
}
