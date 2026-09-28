// What a swing connects with (issue #195, roadmap item 15.4, scope points 4
// and 5).
//
// The swing volume is a `ShapeSweepQuery` and the targets are actor capsules,
// so the narrowphase is capsule against capsule: the shortest distance between
// two segments, compared against the sum of the radii. That is exact rather
// than conservative, and it is the one place a sweep against *actors* differs
// from `ShapeSweeper`, which answers against placed static geometry and grows
// triangles and hulls to do it.
//
// The sweep is sampled the way `ShapeSweeper` samples: a fixed number of steps
// along the travel, nearest touching sample wins, ties broken on the lower
// reference. There is no bisection, and that is deliberate — 15.2 refines the
// touch distance because a tunneling guard and a contact solver need the exact
// moment of contact, whereas a swing needs to know *whether* it connected and
// roughly where, and a quarter-unit error in "where" is invisible. Sampling
// alone also keeps the whole query a pure function of a small array, which is
// what makes the two-overlapping-targets acceptance test a plain unit test.
//
// Filtering, in the order the issue states it:
//
// 1. Actors only. The caller supplies the target list, so a barrel is never in
//    it; this type does not know what a barrel is.
// 2. Never the attacker. Matched on `ReferenceKey`, not on distance — an
//    attacker whose own capsule the swing starts inside would otherwise be the
//    nearest thing to it every single time.
// 3. At most one hit per swing per target. Held by swing id rather than by
//    time, so a graph that fires two `HitFrame` annotations in one attack (the
//    census shows `2_HitFrame` beside `HitFrame`) still lands one hit, while
//    the next swing hits the same target again.
//
// Every target the swing reaches is returned, not just the nearest: a two-
// handed sweep through a crowd hits the crowd, and picking one would be a
// gameplay rule invented here rather than read from anywhere.
//
// Documented in docs/engine/melee-combat.md.

import simd

/// One actor a swing can connect with.
nonisolated struct MeleeTarget: Equatable, Sendable {
    /// Which reference it is, which is also the identity the once-per-swing
    /// filter and the damage application key on.
    let key: ReferenceKey
    /// Capsule bottom, world space.
    let feet: SIMD3<Float>
    /// Its capsule dimensions. Actors share the player's in this milestone;
    /// per-race capsules are not resolved anywhere in the engine yet.
    let capsule: PlayerCapsule

    init(key: ReferenceKey, feet: SIMD3<Float>, capsule: PlayerCapsule = .standard) {
        self.key = key
        self.feet = feet
        self.capsule = capsule
    }

    /// The capsule's core segment, bottom cap centre to top cap centre.
    var segment: (first: SIMD3<Float>, second: SIMD3<Float>) {
        let radius = max(capsule.radius, 0)
        let height = max(capsule.height, radius * 2)
        return (
            feet + SIMD3(0, 0, radius),
            feet + SIMD3(0, 0, height - radius)
        )
    }
}

/// Where a swing touched one target.
nonisolated struct MeleeHit: Equatable, Sendable {
    let target: ReferenceKey
    /// Travel along the swing at which contact was found, world units.
    let distance: Float
    /// Contact point, world space — the midpoint of the closest approach, so
    /// an impact sound is heard between the blade and the body rather than
    /// inside either.
    let position: SIMD3<Float>
}

nonisolated enum MeleeHitDetector {
    /// Steps taken along the swing. `ShapeSweeper` uses 24 for a query whose
    /// answer feeds a solver; a swing needs enough samples that a thin target
    /// cannot slip between two of them, and at 24 steps over a 141-unit reach
    /// the spacing is under 6 units against a 24-unit capsule radius.
    static let sampleCount = 24

    /// Every target `swing` reaches, nearest first, ties broken on the lower
    /// reference so two coincident targets always come back in the same order.
    ///
    /// - Parameters:
    ///   - swing: the volume from `MeleeSwing.volume(feet:capsule:facing:reach:)`.
    ///   - targets: the actors in range. The caller filters to actors; this
    ///     filters out `attacker`.
    ///   - attacker: the swinging reference, never hit by its own swing.
    ///   - alreadyHit: targets this swing has already landed on.
    static func hits(
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
    static func closestApproach(
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
