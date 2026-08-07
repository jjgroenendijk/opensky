// What a projectile hits on one step (issue #196, roadmap item 15.5, scope
// point 4).
//
// ## Which query, and why
//
// The issue offers a choice — the 15.2 shape sweep, or a per-substep raycast
// "where a ray is exact enough" — and asks for the choice to be stated. It is
// split, because the two halves of the world answer to different queries:
//
// * **Static geometry: the 15.2 sweep.** A vanilla arrow flies at thousands of
//   world units per second, so at a 1/120 s substep it covers tens of units
//   between samples. A ray along that segment would be exact for an infinitely
//   thin arrow, and an arrow is *not* infinitely thin: PROJ carries a
//   `collisionRadius`, and honouring it is the difference between an arrow
//   that clips a doorframe and one that slides past it. `ShapeSweeper` sweeps
//   a sphere of that radius along the segment and bisects the touch distance,
//   which is exactly the query, and a zero radius degenerates to the ray
//   without needing a second code path.
// * **Actor capsules: the segment-to-segment test.** `ShapeSweeper` answers
//   against placed static shapes and knows nothing about actors, so the actor
//   half reuses `MeleeHitDetector.closestApproach` — the same exact
//   shortest-distance-between-two-segments narrowphase a swing already uses.
//   Against a capsule that is exact rather than conservative, and it costs one
//   closed-form solve per actor per step instead of a sampled sweep.
//
// Both halves run against the same travelled segment and the nearer touch
// wins, so an arrow that passes an actor standing behind a wall hits the wall.
//
// ## One impact per projectile
//
// Enforced by the projectile ceasing to exist, not by a filter: `first(...)`
// returns at most one impact per step and the runtime retires the projectile on
// it. There is no "already hit" set to keep, because there is no second step.
//
// Pure functions over values. No world, no clock, no mutation.
//
// Documented in docs/engine/archery.md.

import simd

/// Where a projectile touched something, and what.
nonisolated struct ProjectileImpact: Equatable, Sendable {
    /// Travel along the step's segment at which contact was found, world units.
    let distance: Float
    /// Contact point, world space.
    let position: SIMD3<Float>
    /// Surface normal pointing back toward the arrow, where the query supplied
    /// one. Zero against an actor, whose capsule normal is derived instead.
    let normal: SIMD3<Float>
    /// The actor struck, or nil for static geometry.
    let target: ReferenceKey?
    /// The reference struck, where the query named one.
    let reference: FormID?

    var isActor: Bool {
        target != nil
    }
}

/// One step's worth of travel, as the impact query sees it: where the
/// projectile was, where the flight model says it is now, and how thick it is.
///
/// A value rather than three arguments because all three describe the same
/// step, and a caller that mixed one step's endpoints with another's radius
/// would be asking a question about nothing.
nonisolated struct ProjectileStep: Equatable, Sendable {
    let from: SIMD3<Float>
    let to: SIMD3<Float>
    /// PROJ `collisionRadius`. Zero flies as a point, which is a supported case
    /// rather than a degraded one.
    let radius: Float

    /// The radius with its non-finite and negative cases resolved, which is
    /// what every query below actually uses.
    var clampedRadius: Float {
        radius.isFinite ? max(0, radius) : 0
    }
}

nonisolated enum ProjectileImpactQuery {
    /// The nearest thing `step` touches, or nil when it is clear.
    ///
    /// - Parameters:
    ///   - step: the segment the projectile travelled and what it travelled as.
    ///   - targets: the actors in range; the caller filters to actors.
    ///   - shooter: never hit by its own arrow. Matched on `ReferenceKey`
    ///     rather than by distance, because the first step of a shot starts
    ///     inside the shooter's own capsule and it would otherwise be the
    ///     nearest thing to every shot ever fired.
    ///   - sweep: the static-collision query, normally `ShapeSweeper.firstHit`
    ///     over the streamer's broadphase. Passed in so this stays a pure
    ///     function.
    static func first(
        step: ProjectileStep,
        targets: [MeleeTarget],
        shooter: ReferenceKey?,
        sweep: (ShapeSweepQuery) -> ShapeSweepHit?
    ) -> ProjectileImpact? {
        let from = step.from
        let to = step.to
        let travel = to - from
        let distance = simd_length(travel)
        guard distance.isFinite, distance > Float.ulpOfOne else { return nil }
        let radius = step.clampedRadius
        let actorHit = firstActor(
            from: from, to: to, radius: radius, targets: targets, shooter: shooter
        )
        let staticHit = sweep(
            ShapeSweepQuery.sphere(
                center: from, radius: radius, direction: travel, maximumDistance: distance
            )
        )
        guard let staticHit else { return actorHit }
        let asImpact = ProjectileImpact(
            distance: staticHit.distance,
            position: staticHit.position,
            normal: staticHit.normal,
            target: nil,
            reference: staticHit.reference
        )
        guard let actorHit else { return asImpact }
        return actorHit.distance <= staticHit.distance ? actorHit : asImpact
    }

    /// The nearest actor the segment touches, exactly.
    ///
    /// Each capsule is tested once against the whole step segment rather than
    /// at sampled points along it, so a thin actor cannot slip between two
    /// samples of a fast arrow — which at arrow speeds is not a hypothetical.
    static func firstActor(
        from: SIMD3<Float>,
        to: SIMD3<Float>,
        radius: Float,
        targets: [MeleeTarget],
        shooter: ReferenceKey?
    ) -> ProjectileImpact? {
        var best: ProjectileImpact?
        for target in targets where target.key != shooter {
            let contactRadius = radius + max(target.capsule.radius, 0)
            let closest = MeleeHitDetector.closestApproach(
                first: (from, to), second: target.segment
            )
            let separation = simd_distance(closest.onFirst, closest.onSecond)
            guard separation <= contactRadius else { continue }
            let distance = simd_distance(from, closest.onFirst)
            // Ties break on the lower reference, so two coincident actors
            // always answer in the same order — the rule `MeleeHitDetector`
            // and `InteractionRaycaster` both follow.
            let replaces = best.map { current in
                distance < current.distance
                    || (distance == current.distance && target.key < (current.target ?? target.key))
            } ?? true
            guard replaces else { continue }
            let normal = closest.onFirst - closest.onSecond
            best = ProjectileImpact(
                distance: distance,
                position: (closest.onFirst + closest.onSecond) * 0.5,
                normal: simd_length(normal) > Float.ulpOfOne ? simd_normalize(normal) : SIMD3(),
                target: target.key,
                reference: nil
            )
        }
        return best
    }

    /// The rotation a stuck arrow is placed at, so its shaft points along the
    /// direction it arrived from.
    ///
    /// `PlacedReference.Placement` carries Euler radians in the same convention
    /// REFR DATA uses, and `MatrixMath.eulerAngles(of:)` is what the dynamic
    /// solver already converts an orientation through, so the same conversion
    /// is used here rather than a second one that could disagree with it.
    static func stuckRotation(alongFlight direction: SIMD3<Float>) -> SIMD3<Float> {
        let forward = ProjectileFlight.normalized(direction)
        // Yaw about Z, then pitch down from the horizon. Roll is left at zero:
        // an arrow is rotationally symmetric about its own shaft, so there is
        // no third angle to recover and inventing one would only make two
        // identical shots look different.
        let yaw = atan2f(forward.y, forward.x)
        let pitch = asinf(min(max(forward.z, -1), 1))
        return SIMD3(0, -pitch, yaw)
    }
}
