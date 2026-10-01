// What a swing hits: a swept capsule against actor capsules, sampled in fixed steps.
// No bisection, because a swing needs "whether", not the exact moment. The caller
// passes actors only; the attacker is skipped by `ReferenceKey`; each target is hit
// once per swing id. Every target reached is returned, so a sweep hits a crowd.
// See docs/engine/melee-combat.md.

import OpenSkyFormatsESM
import simd

/// Where a swing touched one target.
nonisolated public struct MeleeHit: Equatable, Sendable {
    public let target: ReferenceKey
    /// Travel along the swing at which contact was found, world units.
    public let distance: Float
    /// Contact point, world space — the midpoint of the closest approach, so
    /// an impact sound is heard between the blade and the body rather than
    /// inside either.
    public let position: SIMD3<Float>
}

nonisolated public enum MeleeHitDetector: Sendable {
    /// Steps taken along the swing. `ShapeSweeper` uses 24 for a query whose
    /// answer feeds a solver; a swing needs enough samples that a thin target
    /// cannot slip between two of them, and at 24 steps over a 141-unit reach
    /// the spacing is under 6 units against a 24-unit capsule radius.
    public static let sampleCount = 24

    /// Every target `swing` reaches, nearest first, ties on the lower reference.
    /// `attacker` and `alreadyHit` are skipped.
    public static func hits(
        swing: ShapeSweepQuery,
        targets: [MeleeTarget],
        attacker: ReferenceKey?,
        alreadyHit: Set<ReferenceKey> = []
    ) -> [MeleeHit] {
        guard swing.maximumDistance > 0, swing.radius >= 0 else { return [] }
        let direction = swing.normalizedDirection
        let step = swing.maximumDistance / Float(sampleCount)
        var found: [MeleeHit] = []
        for target in targets {
            guard target.key != attacker, !alreadyHit.contains(target.key) else { continue }
            guard
                let hit = firstTouch(
                    swing: swing, direction: direction, step: step, target: target
                ) else { continue }
            found.append(hit)
        }
        return found.sorted { lhs, rhs in
            (lhs.distance, lhs.target) < (rhs.distance, rhs.target)
        }
    }

    /// The nearest sample at which the swept capsule and the target capsule
    /// overlap, or nil when none does.
    private static func firstTouch(
        swing: ShapeSweepQuery,
        direction: SIMD3<Float>,
        step: Float,
        target: MeleeTarget
    ) -> MeleeHit? {
        let segment = target.segment
        let contactRadius = swing.radius + max(target.capsule.radius, 0)
        for sample in 0 ... sampleCount {
            let travel = min(step * Float(sample), swing.maximumDistance)
            let offset = direction * travel
            let closest = closestApproach(
                first: (swing.first + offset, swing.second + offset),
                second: segment
            )
            guard simd_distance(closest.onFirst, closest.onSecond) <= contactRadius else {
                continue
            }
            return MeleeHit(
                target: target.key,
                distance: travel,
                position: (closest.onFirst + closest.onSecond) * 0.5
            )
        }
        return nil
    }

    /// The closest pair of points on two segments.
    ///
    /// The standard clamped-parameter solution: solve the unconstrained system,
    /// clamp both parameters into `0...1`, and re-solve the second against the
    /// clamped first and back again, which is what makes the parallel and
    /// degenerate cases land on an end point rather than on a divide by zero.
    public static func closestApproach(
        first: (SIMD3<Float>, SIMD3<Float>),
        second: (SIMD3<Float>, SIMD3<Float>)
    ) -> (onFirst: SIMD3<Float>, onSecond: SIMD3<Float>) {
        let firstDirection = first.1 - first.0
        let secondDirection = second.1 - second.0
        let offset = first.0 - second.0
        let firstLengthSquared = simd_length_squared(firstDirection)
        let secondLengthSquared = simd_length_squared(secondDirection)
        let offsetOnSecond = simd_dot(secondDirection, offset)
        let epsilon: Float = 1e-6

        guard firstLengthSquared > epsilon else {
            let parameter = secondLengthSquared > epsilon
                ? clamp(offsetOnSecond / secondLengthSquared)
                : 0
            return (first.0, second.0 + secondDirection * parameter)
        }
        let offsetOnFirst = simd_dot(firstDirection, offset)
        guard secondLengthSquared > epsilon else {
            return (first.0 + firstDirection * clamp(-offsetOnFirst / firstLengthSquared), second.0)
        }
        let projection = simd_dot(firstDirection, secondDirection)
        let denominator = firstLengthSquared * secondLengthSquared - projection * projection
        var onFirst: Float = 0
        if denominator > epsilon {
            onFirst = clamp(
                (projection * offsetOnSecond - offsetOnFirst * secondLengthSquared) / denominator
            )
        }
        var onSecond = (projection * onFirst + offsetOnSecond) / secondLengthSquared
        if onSecond < 0 {
            onSecond = 0
            onFirst = clamp(-offsetOnFirst / firstLengthSquared)
        } else if onSecond > 1 {
            onSecond = 1
            onFirst = clamp((projection - offsetOnFirst) / firstLengthSquared)
        }
        return (
            first.0 + firstDirection * onFirst,
            second.0 + secondDirection * onSecond
        )
    }

    private static func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
