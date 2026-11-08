// When a graph's root motion moves an actor: only while the graph sets
// `bAnimationDriven`, as for an attack, an idle, or a turn in place. Walk and run states
// leave it false, so the mover's speed moves the actor. See docs/engine/actor-graphs.md.

public import OpenSkyBehavior
import simd

/// One graph step's root travel in the world: a move on the ground and a heading turn.
nonisolated public struct ActorRootMotionStep: Equatable, Sendable {
    public let displacement: SIMD2<Float>
    /// Added to the placement's `angleZ`, clockwise from north.
    public let headingTurn: Float

    public init(displacement: SIMD2<Float>, headingTurn: Float) {
        self.displacement = displacement
        self.headingTurn = headingTurn
    }
}

nonisolated public enum ActorGraphRootMotion {
    public static let animationDriven = "bAnimationDriven"
    public static let allowRotation = "bAllowRotation"

    /// The step a graph's root motion makes, or nil while the mover drives the actor.
    /// With `bAllowRotation` the controller keeps the heading, so only the travel applies.
    public static func step(
        _ motion: BehaviorRootMotion?, variables: (String) -> Bool, heading: Float, scale: Float
    ) -> ActorRootMotionStep? {
        guard let motion, motion.isExtracted, variables(animationDriven) else { return nil }
        let forward = SIMD2(sin(heading), cos(heading))
        let right = SIMD2(cos(heading), -sin(heading))
        let local = SIMD2(motion.translation.x, motion.translation.y) * scale
        let turn = variables(allowRotation) ? 0 : -yaw(of: motion.rotation)
        let step = ActorRootMotionStep(
            displacement: forward * local.y + right * local.x, headingTurn: turn
        )
        return step.displacement == .zero && step.headingTurn == 0 ? nil : step
    }

    /// The counter-clockwise turn about +Z a rotation makes.
    static func yaw(of rotation: simd_quatf) -> Float {
        let quaternion = rotation.vector
        return atan2(
            2 * (quaternion.w * quaternion.z + quaternion.x * quaternion.y),
            1 - 2 * (quaternion.y * quaternion.y + quaternion.z * quaternion.z)
        )
    }
}

extension ActorGraphCoordinator {
    func applyRootMotion(
        _ motion: BehaviorRootMotion?, of instance: BehaviorGraphInstance,
        to candidate: ActorGraphCandidate
    ) {
        guard
            let step = ActorGraphRootMotion.step(
                motion,
                variables: { (instance.variable(named: $0)?.realValue ?? 0) != 0 },
                heading: candidate.rotationZ, scale: candidate.scale
            )
        else { return }
        world?.applyRootMotion(step, to: candidate.key)
    }
}
