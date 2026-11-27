import simd

/// Where a summon goes: a target-location spell's aim point, or room in front of the
/// caster of a self-cast summon (docs/engine/magic-archetypes.md).
nonisolated public enum SummonAim: Equatable, Sendable {
    case point(SIMD3<Float>)
    /// `searchRadius` is `fSummonedCreatureSearchRadius`, `largeActorRadius`
    /// `fPathingLargeActorRadius`.
    case ahead(
        searchRadius: Float,
        largeActorRadius: Float = SummonSettings.vanilla.largeActorRadius
    )

    /// How far ahead a self-cast summon aims: both 2D `OBND` radii plus half the search.
    public static func reach(casterRadius: Float, summonRadius: Float, searchRadius: Float)
        -> Float
    {
        casterRadius + summonRadius + 0.5 * searchRadius
    }

    /// How far from the caster the search for a free spot reaches: both radii plus the
    /// whole search radius.
    public static func searchReach(casterRadius: Float, summonRadius: Float, searchRadius: Float)
        -> Float
    {
        casterRadius + summonRadius + searchRadius
    }

    /// A summon wider than `largeActorRadius` uses large-actor pathing.
    public static func usesLargeActorPathing(summonRadius: Float, largeActorRadius: Float)
        -> Bool
    {
        summonRadius > largeActorRadius
    }

    /// The first of `spots`, nearest the aim first, that lies within `reach` of `feet`
    /// and that `accepts` passes: the summon's clearance, then a navmesh path to it.
    public static func freeSpot(
        among spots: [SIMD3<Float>],
        from feet: SIMD3<Float>,
        reach: Float,
        accepts: (SIMD3<Float>) -> Bool
    ) -> SIMD3<Float>? {
        spots.first { spot in
            simd_distance(SIMD2(spot.x, spot.y), SIMD2(feet.x, feet.y)) <= reach && accepts(spot)
        }
    }

    /// The point `reach` ahead of `feet` along `yaw`, counter-clockwise from +X.
    public static func aheadPoint(feet: SIMD3<Float>, yaw: Float, reach: Float) -> SIMD3<Float> {
        feet + SIMD3(cos(yaw), sin(yaw), 0) * reach
    }

    /// Where the summon stands on the line from `feet` to `aim`: short of the first wall
    /// `freeDistance` reports for a sphere of the summon's radius, lifted off the floor.
    public static func standingPoint(
        from feet: SIMD3<Float>,
        toward aim: SIMD3<Float>,
        summonRadius: Float,
        freeDistance: (SIMD3<Float>, Float, SIMD3<Float>, Float) -> Float?
    ) -> SIMD3<Float> {
        let reach = simd_distance(feet, aim)
        guard reach > 1e-3 else { return aim }
        let direction = (aim - feet) / reach
        let radius = max(summonRadius, 1)
        let lift = SIMD3<Float>(0, 0, radius + 1)
        guard let free = freeDistance(feet + lift, radius, direction, reach) else { return aim }
        return feet + direction * max(free, 0)
    }
}
