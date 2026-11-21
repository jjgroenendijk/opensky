// The steering of a flying mount while a target is locked: a strafe term, a term from
// the target's own travel, and a fade with distance.
// docs/engine/combat-assist.md#flying-mount-lock.

import Foundation
import simd

nonisolated public enum FlyingMountLock {
    /// Candidates are gathered this far away, on the ground plane.
    public static let candidateRange: Float = 7500
    /// Both speed terms are divided by this.
    public static let speedScale: Float = 350
    /// The steering fades to nothing at this distance from the target.
    public static let fadeDistance: Float = 750
    /// The strafe-heading factor for a locked actor. A locked object has 0.
    public static let actorStrafeHeadingFactor: Float = 0.5

    /// What one frame of the lock reads.
    public struct Frame: Equatable, Sendable {
        /// The rider's speed, and the strafe input from -1 to 1.
        public var speed: Float = 0
        public var strafe: Float = 0
        /// The rider's heading, as a yaw with `cos` on x and `sin` on y.
        public var heading: Float = 0
        public var distance: Float = 0
        /// The target's travel on the ground plane, in units a second.
        public var targetVelocity = SIMD2<Float>.zero
        public var deltaTime: Float = 0

        public init() {}
    }

    /// The strafe term: the rider's speed × the strafe input / 350.
    public static func strafeTerm(_ frame: Frame) -> Float {
        frame.speed * frame.strafe / speedScale
    }

    /// The target term, only for a moving actor: the angle between its direction of
    /// travel and the heading, folded into -90 to 90 degrees, × its speed / 350 × -2/π.
    public static func targetTerm(_ frame: Frame) -> Float {
        let speed = simd_length(frame.targetVelocity)
        guard speed > 0 else { return 0 }
        let travel = atan2(frame.targetVelocity.y, frame.targetVelocity.x)
        var angle = remainder(travel - frame.heading, 2 * Float.pi)
        if angle > .pi / 2 {
            angle = .pi - angle
        } else if angle < -.pi / 2 {
            angle = -.pi - angle
        }
        return angle * speed / speedScale * (-2 / .pi)
    }

    /// The heading change of this frame, in radians. Zero at 750 units or more.
    public static func headingChange(_ frame: Frame) -> Float {
        let fade = 1 - frame.distance / fadeDistance
        guard fade > 0 else { return 0 }
        let change = (targetTerm(frame) - strafeTerm(frame)) * actorStrafeHeadingFactor
            * frame.deltaTime * fade
        return change.isFinite ? change : 0
    }
}
