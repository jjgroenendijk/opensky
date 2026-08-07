// Joint geometry (issue #197, roadmap item 15.6): turning a joint definition
// and two live bodies into the anchors and angular violations the solver acts
// on. Split from `RagdollConstraintSolver` so the impulse arithmetic and the
// angle measurements can be read — and tested — apart from each other.
//
// ## What the angles mean, and how confident that is
//
// `bhkRagdollConstraint` stores a cone maximum, a plane minimum and maximum, and
// a twist minimum and maximum, per docs/formats/nif-collision.md. What Havok
// does with those five numbers is not published, so the reading below is stated
// rather than assumed, and it is the reading the vanilla numbers are consistent
// with:
//
//  * **Cone** bounds the angle between the two bodies' twist axes. This one is
//    unambiguous — it is what a cone limit means and what the field is named
//    after.
//  * **Plane** bounds the same twist axis's deviation *out of* body A's plane,
//    signed, which is why it stores a minimum and a maximum where the cone
//    stores only a maximum. Together the cone and the plane make the
//    asymmetric, non-circular limit a shoulder needs.
//  * **Twist** bounds the roll of body B about the shared twist axis, measured
//    between the two plane normals.
//
// The uncertainty is real and is recorded in docs/engine/ragdoll.md: the cone
// and twist readings are firm, the plane reading is the one that could be
// something else. It is bounded, though — every reading of these fields
// produces a limit that is *at least* as tight as no limit at all, so a wrong
// one makes a shoulder stiff or loose, never unstable.
//
// Documented in docs/engine/ragdoll.md.

import simd

/// One body's end of a joint, in world space at the current pose.
nonisolated struct RagdollWorldFrame: Sendable {
    let pivot: SIMD3<Float>
    let primaryAxis: SIMD3<Float>
    let secondaryAxis: SIMD3<Float>
}

/// One angular limit found violated: which way it is violated and by how much.
///
/// `axis` is the direction for which `dot(angularVelocityB - angularVelocityA,
/// axis)` is the rate `error` grows at. The solver's whole sign convention rests
/// on that sentence.
nonisolated struct RagdollJointLimitPass: Sendable {
    let axis: SIMD3<Float>
    /// Radians past the limit. Zero or below means the limit is satisfied and
    /// the solver skips it.
    let error: Float

    static let satisfied = RagdollJointLimitPass(axis: SIMD3(0, 0, 1), error: 0)

    /// Every limit slot of one joint, in a fixed order so that a slot's
    /// accumulated impulse means the same thing on every iteration. Always four
    /// entries; unused and satisfied slots come back with a zero error.
    static func passes(
        of joint: RagdollJointDefinition,
        frames: (a: RagdollWorldFrame, b: RagdollWorldFrame)
    ) -> [RagdollJointLimitPass] {
        switch joint.limits {
        case .point, .distance:
            [satisfied, satisfied, satisfied, satisfied]
        case .hinge:
            [axisAlignment(frames), satisfied, satisfied, satisfied]
        case let .limitedHinge(minAngle, maxAngle):
            [
                axisAlignment(frames),
                hingeAngle(frames, minAngle: minAngle, maxAngle: maxAngle),
                satisfied,
                satisfied
            ]
        case let .cone(coneMax, planeMin, planeMax, twistMin, twistMax):
            [
                cone(frames, maxAngle: coneMax),
                plane(frames, minAngle: planeMin, maxAngle: planeMax),
                twist(frames, minAngle: twistMin, maxAngle: twistMax),
                satisfied
            ]
        }
    }

    // MARK: - The four measurements

    /// A hinge's two rotation axes must stay parallel. Two-sided, so it is
    /// expressed as a limit of zero that is violated whenever the axes are not
    /// aligned; the correction axis flips with the misalignment, which is what
    /// makes a one-sided impulse enough.
    private static func axisAlignment(
        _ frames: (a: RagdollWorldFrame, b: RagdollWorldFrame)
    ) -> RagdollJointLimitPass {
        let angle = RagdollMath.angle(between: frames.a.primaryAxis, and: frames.b.primaryAxis)
        guard angle > 0 else { return satisfied }
        guard
            let axis = RagdollMath.unit(
                simd_cross(frames.a.primaryAxis, frames.b.primaryAxis)
            )
        else {
            // Exactly antiparallel: the cross product carries no direction, so
            // any perpendicular will do to start the rotation back.
            guard let fallback = RagdollMath.anyPerpendicular(frames.a.primaryAxis) else {
                return satisfied
            }
            return RagdollJointLimitPass(axis: fallback, error: angle)
        }
        return RagdollJointLimitPass(axis: axis, error: angle)
    }

    /// The cone: the angle between the two twist axes, bounded above.
    private static func cone(
        _ frames: (a: RagdollWorldFrame, b: RagdollWorldFrame),
        maxAngle: Float
    ) -> RagdollJointLimitPass {
        guard maxAngle.isFinite else { return satisfied }
        let angle = RagdollMath.angle(between: frames.a.primaryAxis, and: frames.b.primaryAxis)
        let error = angle - max(0, maxAngle)
        guard error > 0 else { return satisfied }
        guard
            let axis = RagdollMath.unit(
                simd_cross(frames.a.primaryAxis, frames.b.primaryAxis)
            ) ?? RagdollMath.anyPerpendicular(frames.a.primaryAxis)
        else { return satisfied }
        return RagdollJointLimitPass(axis: axis, error: error)
    }

    /// The plane: body B's twist axis leaving body A's plane, bounded on both
    /// sides.
    ///
    /// Rotating B about `cross(twistB, planeNormalA)` is what raises
    /// `dot(twistB, planeNormalA)`, and therefore the signed angle out of the
    /// plane — which is the convention the solver's axis must satisfy.
    private static func plane(
        _ frames: (a: RagdollWorldFrame, b: RagdollWorldFrame),
        minAngle: Float,
        maxAngle: Float
    ) -> RagdollJointLimitPass {
        guard minAngle.isFinite, maxAngle.isFinite, minAngle <= maxAngle else {
            return satisfied
        }
        let normal = frames.a.secondaryAxis
        let angle = asin(min(max(simd_dot(frames.b.primaryAxis, normal), -1), 1))
        guard angle.isFinite else { return satisfied }
        guard
            let axis = RagdollMath.unit(simd_cross(frames.b.primaryAxis, normal))
        else { return satisfied }
        if angle > maxAngle {
            return RagdollJointLimitPass(axis: axis, error: angle - maxAngle)
        }
        if angle < minAngle {
            return RagdollJointLimitPass(axis: -axis, error: minAngle - angle)
        }
        return satisfied
    }

    /// The roll about the shared axis, bounded on both sides. A ragdoll cone's
    /// twist limit and a limited hinge's own angle are the same measurement.
    ///
    /// The angle runs from **B's** reference axis to **A's**, which is the one
    /// detail here that was settled by measurement rather than by reasoning.
    /// Read at the vanilla humanoid's bind pose, this direction puts all four
    /// hinge kinds the skeleton carries inside their authored ranges — knee
    /// -0.054 in [-1.920, 0], ankle -0.498 in [-0.596, 0.063], elbow +0.019 in
    /// [0, 1.920], wrist -0.060 in [-0.087, 0.349]. The opposite direction puts
    /// three of the four outside, the ankle by 0.44 radians, which would have a
    /// standing skeleton fighting its own ankle limit before anything moved.
    /// The vanilla cones all carry symmetric twist ranges, so they cannot tell
    /// the two directions apart and follow the hinges for consistency.
    ///
    /// Because the angle is A-relative-to-B, the axis the solver is handed is
    /// negated: its contract is that `dot(angularVelocityB - angularVelocityA,
    /// axis)` is the rate the violation grows at, and rotating A is what grows
    /// this one.
    private static func twist(
        _ frames: (a: RagdollWorldFrame, b: RagdollWorldFrame),
        minAngle: Float,
        maxAngle: Float
    ) -> RagdollJointLimitPass {
        guard minAngle.isFinite, maxAngle.isFinite, minAngle <= maxAngle else {
            return satisfied
        }
        // The average of the two axes rather than either one: while the cone is
        // being violated the two disagree, and measuring a roll about one of
        // them makes the angle jump as the cone recovers.
        guard
            let axis = RagdollMath.unit(frames.a.primaryAxis + frames.b.primaryAxis),
            let angle = RagdollMath.signedAngle(
                from: frames.b.secondaryAxis, to: frames.a.secondaryAxis, about: axis
            )
        else { return satisfied }
        if angle > maxAngle {
            return RagdollJointLimitPass(axis: -axis, error: angle - maxAngle)
        }
        if angle < minAngle {
            return RagdollJointLimitPass(axis: axis, error: minAngle - angle)
        }
        return satisfied
    }

    /// The hinge's own rotation angle, measured between the two perpendicular
    /// reference axes about the shared hinge axis.
    private static func hingeAngle(
        _ frames: (a: RagdollWorldFrame, b: RagdollWorldFrame),
        minAngle: Float,
        maxAngle: Float
    ) -> RagdollJointLimitPass {
        twist(frames, minAngle: minAngle, maxAngle: maxAngle)
    }
}

nonisolated extension RagdollJointDefinition {
    /// Both bodies exist in `bodies`. Checked once per visit rather than
    /// trusted, because a definition and a body list are assembled separately.
    func isResolvable(in bodies: [DynamicBody]) -> Bool {
        bodies.indices.contains(bodyA) && bodies.indices.contains(bodyB)
    }

    /// Both anchors in world space at the current pose.
    func anchors(in bodies: [DynamicBody]) -> (a: SIMD3<Float>, b: SIMD3<Float>) {
        (
            a: bodies[bodyA].position + bodies[bodyA].orientation.act(frameA.pivot),
            b: bodies[bodyB].position + bodies[bodyB].orientation.act(frameB.pivot)
        )
    }

    /// Both frames in world space at the current pose.
    func worldFrames(
        in bodies: [DynamicBody]
    ) -> (a: RagdollWorldFrame, b: RagdollWorldFrame) {
        (a: frameA.world(in: bodies[bodyA]), b: frameB.world(in: bodies[bodyB]))
    }
}

nonisolated extension RagdollJointFrame {
    func world(in body: DynamicBody) -> RagdollWorldFrame {
        RagdollWorldFrame(
            pivot: body.position + body.orientation.act(pivot),
            primaryAxis: body.orientation.act(primaryAxis),
            secondaryAxis: body.orientation.act(secondaryAxis)
        )
    }
}

/// Small vector routines the joint solver needs and `simd` does not supply, each
/// written to return nothing rather than a NaN on degenerate input.
nonisolated enum RagdollMath {
    /// The cross-product matrix of `vector`, so that `skew(v) * w == cross(v, w)`.
    static func skew(_ vector: SIMD3<Float>) -> float3x3 {
        float3x3(
            SIMD3(0, vector.z, -vector.y),
            SIMD3(-vector.z, 0, vector.x),
            SIMD3(vector.y, -vector.x, 0)
        )
    }

    /// A unit vector, or nil when there is no direction to extract.
    static func unit(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
        let lengthSquared = simd_length_squared(vector)
        guard lengthSquared.isFinite, lengthSquared > 1e-12 else { return nil }
        return vector / lengthSquared.squareRoot()
    }

    /// Unsigned angle between two directions, in radians. Zero for anything
    /// degenerate, which reads as "no violation" everywhere it is used.
    static func angle(between first: SIMD3<Float>, and second: SIMD3<Float>) -> Float {
        guard let lhs = unit(first), let rhs = unit(second) else { return 0 }
        let angle = acos(min(max(simd_dot(lhs, rhs), -1), 1))
        return angle.isFinite ? angle : 0
    }

    /// Signed angle from `first` to `second` measured about `axis`, in radians
    /// over `-pi ... pi`. Both inputs are projected perpendicular to the axis
    /// first, because a roll is only defined for the components that are free to
    /// roll.
    static func signedAngle(
        from first: SIMD3<Float>,
        to second: SIMD3<Float>,
        about axis: SIMD3<Float>
    ) -> Float? {
        guard
            let normal = unit(axis),
            let lhs = unit(first - normal * simd_dot(first, normal)),
            let rhs = unit(second - normal * simd_dot(second, normal))
        else { return nil }
        let angle = atan2(simd_dot(simd_cross(lhs, rhs), normal), simd_dot(lhs, rhs))
        return angle.isFinite ? angle : nil
    }

    /// Some unit vector perpendicular to `axis`, for the antiparallel case where
    /// a cross product carries no direction at all.
    static func anyPerpendicular(_ axis: SIMD3<Float>) -> SIMD3<Float>? {
        guard let normal = unit(axis) else { return nil }
        let reference = abs(normal.z) < 0.9
            ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(1, 0, 0)
        return unit(simd_cross(normal, reference))
    }
}
