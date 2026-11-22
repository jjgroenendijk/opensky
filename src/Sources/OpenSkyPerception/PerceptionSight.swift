// The geometry half of perception: distance and facing between two poses.
// Split from `DetectionFormula`, which turns these into a detection value.
// Line of sight is a world query and lives on `PerceptionWorld`.
// See docs/engine/detection.md.

import Foundation
import OpenSkyPerceptionInterface
import simd

nonisolated enum PerceptionSight: Sendable {
    /// Whether `target` lies in the yaw cone of half-angle `cosine` about the
    /// observer's heading. Height is ignored, because no actor here pitches its head.
    /// A target with zero horizontal offset is inside every cone.
    static func isInViewCone(
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

    /// From this angle off the facing the range of a sight line starts to shrink.
    static let fullRangeDegrees: Float = 60
    /// The share of the range left directly behind the observer.
    static let interiorRangeBehind: Float = 0.75
    static let exteriorRangeBehind: Float = 0.5
    private static let behindDegrees: Float = 180

    /// The share of the range a sight line keeps at `degrees` off the observer's
    /// facing: 1 up to 60 degrees, then a straight line down to the share behind.
    /// docs/engine/detection.md#range-and-view-cone.
    static func sightRangeShare(degreesOffFacing degrees: Float, isExterior: Bool) -> Float {
        let behind = isExterior ? exteriorRangeBehind : interiorRangeBehind
        guard degrees.isFinite, degrees > fullRangeDegrees else { return 1 }
        let part = (min(degrees, behindDegrees) - fullRangeDegrees)
            / (behindDegrees - fullRangeDegrees)
        return 1 + (behind - 1) * part
    }

    /// The angle from the observer's facing to the target, in degrees, on the ground
    /// plane. 0 for a target at the observer's own place.
    static func degreesOffFacing(observer: PerceptionObserver, target: PerceptionTarget) -> Float {
        let offset = SIMD2(target.feet.x - observer.feet.x, target.feet.y - observer.feet.y)
        let length = simd_length(offset)
        guard length.isFinite, length > Float.ulpOfOne else { return 0 }
        let cosine = min(max(simd_dot(offset / length, observer.heading), -1), 1)
        return acosf(cosine) * behindDegrees / .pi
    }

    /// Straight-line distance between a pair, world units. Feet to feet, so a
    /// crouching target is not reported as further away than a standing one.
    static func distance(observer: PerceptionObserver, target: PerceptionTarget) -> Float {
        let separation = simd_distance(observer.feet, target.feet)
        return separation.isFinite ? separation : .greatestFiniteMagnitude
    }
}
