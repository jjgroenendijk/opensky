// A decoded skeleton assembled in code: the input the ragdoll build takes,
// without any NIF bytes (issue #197, item 15.6; extended for issue #413).
//
// Shared by `RagdollDefinitionTests`, which is about the resolution step, and
// `RagdollSelfCollisionTests`, which is about the biped filter bits the same
// bodies carry. Both want the same two-or-more-bone skeleton and differ only in
// what they put in the `HavokFilter`, so the filters are a parameter and
// everything else is fixed.

@testable import opensky
import simd

enum RagdollSkeletonFixture {
    /// Bones a spacing apart along x, each with a capsule body centred on its
    /// bone, consecutive pairs joined by a ragdoll cone at the midpoint.
    static let spacing: Float = 30

    /// The block index the body for bone `index` answers to. The joint blocks
    /// are derived from these, so a test asserting on a reported skip can name
    /// the block it expects.
    static func block(of index: Int) -> Int {
        100 + index
    }

    static func bindMatrices(count: Int) -> [float4x4] {
        (0 ..< count).map { MatrixMath.translation(SIMD3(Float($0) * spacing, 0, 0)) }
    }

    /// One collision body per named bone, plus a ragdoll cone joining each
    /// consecutive pair at the midpoint between them.
    ///
    /// The pivots are authored in each body's own entity space, exactly as a NIF
    /// authors them: the joint sits at `+spacing/2` from the first body and
    /// `-spacing/2` from the second.
    ///
    /// `filters` are index-aligned with `boneNames`; a name past the end of the
    /// list gets the inert static filter, which carries no biped part.
    static func model(
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
    static func coneBlock(entityA: Int, entityB: Int) -> Int {
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
