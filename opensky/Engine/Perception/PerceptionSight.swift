// The geometry half of perception (issue #202, roadmap item 16.6): where a pair
// stands relative to each other, and whether the observer is facing the target.
//
// Pure functions over points, split from `DetectionFormula` because they answer
// a different kind of question. The formula turns numbers into a detection
// value; this file turns two poses into the two booleans and one distance the
// formula takes. The third input the formula needs — whether anything is in the
// way — is a world query and lives on `PerceptionWorld`, because it is the only
// part of perception that cannot be answered from the pair alone.
//
// Documented in docs/engine/detection.md.

import Foundation
import simd

nonisolated enum PerceptionSight {
    /// Whether `target` lies inside a cone of half-angle `cosine` about
    /// `observer`'s heading.
    ///
    /// A yaw cone: the offset is flattened into the XY plane before the angle
    /// is taken, so a target on a balcony directly ahead is inside the cone and
    /// one directly behind at the same height is not. Nothing in this engine
    /// pitches an actor's head, so a solid-angle test would differ from this
    /// one only by rejecting targets an actor would in fact see.
    ///
    /// A target standing exactly on the observer — zero horizontal offset — is
    /// inside every cone. It has no direction to be outside one in, and
    /// reporting "not seen" for something occupying your own space would be the
    /// stranger answer.
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

    /// Straight-line distance between a pair, world units. Feet to feet, so a
    /// crouching target is not reported as further away than a standing one.
    static func distance(observer: PerceptionObserver, target: PerceptionTarget) -> Float {
        let separation = simd_distance(observer.feet, target.feet)
        return separation.isFinite ? separation : .greatestFiniteMagnitude
    }
}
