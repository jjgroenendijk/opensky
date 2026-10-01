// One actor's ragdoll: a body per skeleton bone, the joints between them, and bind-pose
// frames. Built from `bhkRigidBody` and constraint blocks (docs/formats/nif-collision.md).
// Pivots move from entity space to centre-of-mass space; axes take only the rotation.
// `animatedBoneMatrix * bindInverse` carries a body from bind pose to the animation.
// See docs/engine/ragdoll-solver.md.

import simd

/// One simulated bone: the body that stands for it and the bind-pose frame that
/// ties the body to the animation skeleton.
nonisolated public struct RagdollBoneDefinition: Sendable {
    /// The `NiNode` the `bhkBlendCollisionObject` targeted, which on a character
    /// skeleton is the animation bone's own name (`NPC L Calf [LClf]`).
    public let boneName: String
    /// Index into the animation skeleton's bone list, resolved by name.
    public let boneIndex: Int
    public let body: DynamicBodyDefinition
    /// Where the animation skeleton draws this bone with nothing animated, in
    /// the model space the bodies were built in.
    public let bindBoneMatrix: float4x4
    /// `bindBoneMatrix.inverse`, kept rather than recomputed because the
    /// hand-off multiplies by it once per bone per activation.
    public let bindBoneInverse: float4x4
    /// The `BipedPart` the source body's `HavokFilter` named, which is what
    /// decides who this bone may collide with (`RagdollSelfCollision`). Nil on a
    /// body whose filter names no biped layer, and nil by default so a synthetic
    /// fixture that says nothing about parts self-collides with nothing.
    public let bipedPart: UInt8?

    public init(
        boneName: String,
        boneIndex: Int,
        body: DynamicBodyDefinition,
        bindBoneMatrix: float4x4,
        bipedPart: UInt8? = nil
    ) {
        self.boneName = boneName
        self.boneIndex = boneIndex
        self.body = body
        self.bindBoneMatrix = bindBoneMatrix
        self.bipedPart = bipedPart
        bindBoneInverse = bindBoneMatrix.inverse
    }
}

/// One body's end of a joint, in its centre-of-mass frame. Three axes cover every
/// class solved here; a ball-and-socket leaves the identity basis.
nonisolated public struct RagdollJointFrame: Sendable {
    public let pivot: SIMD3<Float>
    /// The cone's central axis on a ragdoll joint, the rotation axis on a hinge.
    public let primaryAxis: SIMD3<Float>
    /// The plane normal on a ragdoll joint, the first perpendicular on a hinge.
    /// This is the axis a twist angle is measured from.
    public let secondaryAxis: SIMD3<Float>

    public static let identity = RagdollJointFrame(
        pivot: .zero,
        primaryAxis: SIMD3<Float>(1, 0, 0),
        secondaryAxis: SIMD3<Float>(0, 1, 0)
    )
}

/// What a joint constrains besides its pivots. Only ragdoll cones, limited hinges and
/// hinges carry limits (docs/formats/nif-collision.md); others are `.point` and tallied.
nonisolated public enum RagdollJointLimits: Sendable {
    /// Pivots held together, rotation free.
    case point
    /// Pivots held `length` engine units apart, rotation free.
    case distance(length: Float)
    /// The two primary axes held parallel, rotation about them free.
    case hinge
    /// The two primary axes held parallel, rotation about them bounded.
    case limitedHinge(minAngle: Float, maxAngle: Float)
    /// A cone on the twist axis, an asymmetric limit out of the plane, and a
    /// bounded twist about the axis. All angles radians.
    case cone(
        coneMaxAngle: Float,
        planeMinAngle: Float,
        planeMaxAngle: Float,
        twistMinAngle: Float,
        twistMaxAngle: Float
    )
}

/// One joint: the two bodies it binds, each body's end of it, what it limits,
/// and how much it resists being moved.
nonisolated public struct RagdollJointDefinition: Sendable {
    /// Indices into `RagdollDefinition.bones`, always distinct and in range.
    public let bodyA: Int
    public let bodyB: Int
    public let frameA: RagdollJointFrame
    public let frameB: RagdollJointFrame
    public let limits: RagdollJointLimits
    /// Raw `maxFriction`. The unit is unpublished, so it is read as the fraction of
    /// relative spin removed per second (docs/engine/ragdoll-solver.md). A wrong scale
    /// changes stiffness, never stability.
    public let maxFriction: Float

    public init(
        bodyA: Int,
        bodyB: Int,
        frameA: RagdollJointFrame,
        frameB: RagdollJointFrame,
        limits: RagdollJointLimits,
        maxFriction: Float = 0
    ) {
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.frameA = frameA
        self.frameB = frameB
        self.limits = limits
        self.maxFriction = maxFriction.isFinite ? max(0, maxFriction) : 0
    }
}

/// Why a decoded body or joint did not make it into the definition. Collected
/// rather than thrown: a ragdoll missing one limb is more useful than none, and
/// the acceptance gate wants to assert that the vanilla humanoid skeleton
/// produces an empty list.
nonisolated public enum RagdollBuildSkip: Equatable, Sendable {
    /// A body whose target node names no bone of the animation skeleton.
    case unresolvedBoneName(String)
    /// A body with no name at all, so nothing could be resolved.
    case unnamedBody(block: Int)
    /// A body whose shapes or mass could not make a simulable definition.
    case unsimulableBody(String)
    /// A joint whose entity pointer names a body that is not in the definition.
    case unresolvedJointEnd(block: Int)
    /// A joint class that decodes but carries no limits this solver enforces.
    case unlimitedJointClass(String)
}

/// One actor's whole ragdoll.
nonisolated public struct RagdollDefinition: Sendable {
    public let bones: [RagdollBoneDefinition]
    public let joints: [RagdollJointDefinition]
    /// Everything the build dropped, in the order it was dropped.
    public let skipped: [RagdollBuildSkip]
    /// Which of this ragdoll's bones may touch, from biped part numbers and the joint
    /// graph. Derived once, because none of it moves.
    public let selfCollision: RagdollSelfCollision

    public var boneCount: Int {
        bones.count
    }

    public var jointCount: Int {
        joints.count
    }

    public init(
        bones: [RagdollBoneDefinition],
        joints: [RagdollJointDefinition],
        skipped: [RagdollBuildSkip] = []
    ) {
        self.bones = bones
        self.joints = joints
        self.skipped = skipped
        selfCollision = RagdollSelfCollision(bones: bones, joints: joints)
    }
}
