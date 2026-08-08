// The iteration seam that lets DynamicBodySolver interleave ragdoll joints
// with contacts. Split from RagdollConstraintSolver for the type-length limit.

nonisolated extension RagdollConstraintSolver {
    /// Accumulated impulses shared by the velocity iterations of one substep.
    /// The dynamic solver owns this state when contacts and joints are
    /// interleaved, so neither constraint family has to restart from zero.
    struct VelocityState {
        fileprivate var limits: [RagdollLimitImpulses]

        init(jointCount: Int) {
            limits = [RagdollLimitImpulses](
                repeating: RagdollLimitImpulses(), count: jointCount
            )
        }
    }

    /// Runs one velocity iteration. Internal so the dynamic solver can place a
    /// contact iteration before or after it inside the same fixed-point solve.
    static func solveVelocityIteration(
        joints: [RagdollJointDefinition],
        bodies: inout [DynamicBody],
        iterationTime: Float,
        state: inout VelocityState
    ) -> Int {
        guard state.limits.count == joints.count else { return 0 }
        var violations = 0
        for (index, joint) in joints.enumerated() {
            guard joint.isResolvable(in: bodies) else { continue }
            applyFriction(joint, bodies: &bodies, dt: iterationTime)
            solvePoint(joint, bodies: &bodies)
            violations += solveLimits(
                joint, accumulated: &state.limits[index], bodies: &bodies
            )
        }
        return violations
    }

    /// Applies position and orientation recovery after every velocity
    /// constraint has converged for the substep.
    static func correctPoses(
        joints: [RagdollJointDefinition],
        bodies: inout [DynamicBody],
        includeSleeping: Bool = false
    ) {
        correctLimits(joints: joints, bodies: &bodies, includeSleeping: includeSleeping)
        correctPositions(joints: joints, bodies: &bodies, includeSleeping: includeSleeping)
    }
}
