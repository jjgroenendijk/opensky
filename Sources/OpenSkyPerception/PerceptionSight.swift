// The geometry half of perception: distance and facing between two poses.
// Split from `DetectionFormula`, which turns these into a detection value.
// Line of sight is a world query and lives on `PerceptionWorld`.
// See docs/engine/detection.md.

import Foundation
import OpenSkyPerceptionInterface
import simd

nonisolated public enum PerceptionSight: Sendable {
    /// Whether `target` lies in the yaw cone of half-angle `cosine` about the
    /// observer's heading. Height is ignored, because no actor here pitches its head.
    /// A target with zero horizontal offset is inside every cone.
    public static func isInViewCone(
        observer: PerceptionObserver,
        target: PerceptionTarget,
        cosine: Float
    ) -> Bool {
        let offset = SIMD2(target.feet.x - observer.feet.x, target.feet.y - observer.feet.y)
        let length = simd_length(offset)
        guard length.isFinite else { return false }
        guard length > Float.ulpOfOne else { return true }
        let heading = observer.heading
        return simd_dot(offset / length, heading) >= cosine
    }

    /// Straight-line distance between a pair, world units. Feet to feet, so a
    /// crouching target is not reported as further away than a standing one.
    public static func distance(observer: PerceptionObserver, target: PerceptionTarget) -> Float {
        let separation = simd_distance(observer.feet, target.feet)
        return separation.isFinite ? separation : .greatestFiniteMagnitude
    }
}
