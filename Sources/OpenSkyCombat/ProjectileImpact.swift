// What a projectile hits on one step. Static geometry uses a sphere sweep of
// the PROJ `collisionRadius`; actor capsules use the segment test of
// `MeleeHitDetector.closestApproach`. The nearer touch wins. The runtime retires
// a projectile on its first impact. Pure functions over values.
// See docs/engine/projectiles.md.

import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

/// Where a projectile touched something, and what.
nonisolated public struct ProjectileImpact: Equatable, Sendable {
    /// Travel along the step's segment at which contact was found, world units.
    public let distance: Float
    /// Contact point, world space.
    public let position: SIMD3<Float>
    /// The actor struck, or nil for static geometry.
    public let target: ReferenceKey?
    /// The reference struck, where the query named one.
    public let reference: FormID?
    /// The MATT type of the static surface struck. Nil for an actor, which
    /// carries no material yet, so the impact data set's default entry plays.
    public var material: FormID?
    /// The struck surface's normal, for a decal. Nil for an actor.
    public var normal: SIMD3<Float>?

    public var isActor: Bool {
        target != nil
    }
}

/// One step's worth of travel, as the impact query sees it: where the
/// projectile was, where the flight model says it is now, and how thick it is.
///
/// A value rather than three arguments because all three describe the same
/// step, and a caller that mixed one step's endpoints with another's radius
/// would be asking a question about nothing.
nonisolated public struct ProjectileStep: Equatable, Sendable {
    public let from: SIMD3<Float>
    public let to: SIMD3<Float>
    /// PROJ `collisionRadius`. Zero flies as a point, which is a supported case
    /// rather than a degraded one.
    public let radius: Float

    /// The radius with its non-finite and negative cases resolved, which is
    /// what every query below actually uses.
    public var clampedRadius: Float {
        radius.isFinite ? max(0, radius) : 0
    }

    public init(from: SIMD3<Float>, to: SIMD3<Float>, radius: Float) {
        self.from = from
        self.to = to
        self.radius = radius
    }
}

nonisolated public enum ProjectileImpactQuery: Sendable {
    /// The nearest thing `step` touches, or nil when it is clear.
    /// - Parameters:
    ///   - step: the segment the projectile travelled and its shape.
    ///   - targets: the actors in range.
    ///   - shooter: never hit by its own shot, matched on `ReferenceKey`.
    ///   - sweep: the static query, normally `ShapeSweeper.firstHit`.
    public static func first(
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
            target: nil,
            reference: staticHit.reference,
            material: staticHit.material,
            normal: staticHit.normal
        )
        guard let actorHit else { return asImpact }
        return actorHit.distance <= staticHit.distance ? actorHit : asImpact
    }

    /// The nearest actor the segment touches, exactly.
    ///
    /// Each capsule is tested once against the whole step segment rather than
    /// at sampled points along it, so a thin actor cannot slip between two
    /// samples of a fast arrow — which at arrow speeds is not a hypothetical.
    public static func firstActor(
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
            best = ProjectileImpact(
                distance: distance,
                position: (closest.onFirst + closest.onSecond) * 0.5,
                target: target.key,
                reference: nil
            )
        }
        return best
    }

    /// The rotation a stuck arrow is placed at, so its shaft points along its flight.
    /// Uses `MatrixMath.eulerAngles(of:)`, the conversion REFR placements use.
    public static func stuckRotation(alongFlight direction: SIMD3<Float>) -> SIMD3<Float> {
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
