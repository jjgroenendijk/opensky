// The immutable description of one actor's ragdoll (issue #197, roadmap item
// 15.6): one rigid body per skeleton bone, the joints between them, and the
// bind-pose frames that carry an animated pose onto the bodies and back.
//
// A skeleton NIF carries no ragdoll container class. What it carries is a set of
// `bhkRigidBody` blocks each hanging off a `bhkBlendCollisionObject` that targets
// a named `NiNode`, plus `bhkRagdollConstraint` and `bhkLimitedHingeConstraint`
// blocks binding pairs of those bodies (docs/formats/nif-collision.md). This type
// is the step from that decode to something the solver can advance: bodies
// resolved onto animation-skeleton bones by name, joints resolved onto body
// indices, and every pivot and axis re-expressed in the frame the solver works
// in.
//
// Two coordinate rules do all the work here and are worth stating once.
//
//  * A body's own frame is centre-of-mass local, because that is the frame
//    `DynamicBodyDefinition` re-centres its shapes into and the point every
//    impulse is measured against. A constraint pivot arrives in the *entity's*
//    local space — the space the `bhkRigidBody`'s shapes are authored in, before
//    `NIFCollisionBody.transform` places it — so it is carried into model space
//    by that transform and then offset by the body's centre of mass. Axes take
//    the rotation half of the same transform and nothing else.
//  * A bone's own frame is the bind pose. `bindBoneMatrix` is where the
//    animation skeleton draws the bone when nothing has moved, in the same model
//    space the bodies were built in, so `animatedBoneMatrix * bindInverse` is the
//    rigid transform that carries a body from its bind placement to wherever the
//    animation has taken the bone. Handing a ragdoll off from an animated pose is
//    that product, and writing a simulated bone back is its inverse.
//
// Documented in docs/engine/ragdoll.md.

import simd

/// One simulated bone: the body that stands for it and the bind-pose frame that
/// ties the body to the animation skeleton.
nonisolated struct RagdollBoneDefinition: Sendable {
    /// The `NiNode` the `bhkBlendCollisionObject` targeted, which on a character
    /// skeleton is the animation bone's own name (`NPC L Calf [LClf]`).
    let boneName: String
    /// Index into the animation skeleton's bone list, resolved by name.
    let boneIndex: Int
    let body: DynamicBodyDefinition
    /// Where the animation skeleton draws this bone with nothing animated, in
    /// the model space the bodies were built in.
    let bindBoneMatrix: float4x4
    /// `bindBoneMatrix.inverse`, kept rather than recomputed because the
    /// hand-off multiplies by it once per bone per activation.
    let bindBoneInverse: float4x4

    init(
        boneName: String,
        boneIndex: Int,
        body: DynamicBodyDefinition,
        bindBoneMatrix: float4x4
    ) {
        self.boneName = boneName
        self.boneIndex = boneIndex
        self.body = body
        self.bindBoneMatrix = bindBoneMatrix
        bindBoneInverse = bindBoneMatrix.inverse
    }
}

/// One body's end of a joint, in that body's centre-of-mass-local frame.
///
/// Three axes rather than a named set, because every constraint class this
/// engine solves describes its end with at most three: a ragdoll cone names
/// twist, plane and motor, a hinge names its rotation axis and two
/// perpendiculars, and a ball-and-socket names none at all and leaves them at
/// the identity basis.
nonisolated struct RagdollJointFrame: Sendable {
    let pivot: SIMD3<Float>
    /// The cone's central axis on a ragdoll joint, the rotation axis on a hinge.
    let primaryAxis: SIMD3<Float>
    /// The plane normal on a ragdoll joint, the first perpendicular on a hinge.
    /// This is the axis a twist angle is measured from.
    let secondaryAxis: SIMD3<Float>

    static let identity = RagdollJointFrame(
        pivot: .zero,
        primaryAxis: SIMD3<Float>(1, 0, 0),
        secondaryAxis: SIMD3<Float>(0, 1, 0)
    )
}

/// What a joint constrains beyond holding its two pivots together.
///
/// Only the three shapes the vanilla census actually produces carry limits:
/// 624 ragdoll cones and 512 limited hinges over 751 bone pairs, plus three
/// plain hinges on clutter (docs/formats/nif-collision.md). Everything else
/// decodes to `.point` and is tallied, because a joint held at its pivot with
/// its rotation free is a visibly loose limb rather than an invented limit.
nonisolated enum RagdollJointLimits: Sendable {
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
nonisolated struct RagdollJointDefinition: Sendable {
    /// Indices into `RagdollDefinition.bones`, always distinct and in range.
    let bodyA: Int
    let bodyB: Int
    let frameA: RagdollJointFrame
    let frameB: RagdollJointFrame
    let limits: RagdollJointLimits
    /// `bhkRagdollConstraint`/`bhkLimitedHingeConstraint` `maxFriction`, raw as
    /// the file stores it.
    ///
    /// Havok does not publish the unit, and the vanilla humanoid authors only
    /// two values across its seventeen joints — 10.0 on every cone and 0.01 on
    /// every limited hinge — so there is no distribution to infer one from. This
    /// engine therefore reads it as a *rate*: the fraction of the joint's
    /// relative angular velocity that the joint's own resistance removes per
    /// second. That reading is a modelling choice, recorded as such in
    /// docs/engine/ragdoll.md, and it is bounded in the only way that matters —
    /// friction can only ever take energy out, so a wrong scale makes a corpse
    /// stiff or floppy and can never make one unstable.
    let maxFriction: Float

    init(
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
nonisolated enum RagdollBuildSkip: Equatable, Sendable {
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
nonisolated struct RagdollDefinition: Sendable {
    let bones: [RagdollBoneDefinition]
    let joints: [RagdollJointDefinition]
    /// Everything the build dropped, in the order it was dropped.
    let skipped: [RagdollBuildSkip]

    var boneCount: Int {
        bones.count
    }

    var jointCount: Int {
        joints.count
    }

    init(
        bones: [RagdollBoneDefinition],
        joints: [RagdollJointDefinition],
        skipped: [RagdollBuildSkip] = []
    ) {
        self.bones = bones
        self.joints = joints
        self.skipped = skipped
    }
}
