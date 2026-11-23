// Which actor the melee magnetism rule turns with: the nearest one the view ray passes
// through. docs/engine/combat-assist.md#in-opensky.

public import OpenSkyFormatsESM
public import OpenSkyPhysics
public import OpenSkyWorldInterface
import simd

nonisolated public enum MeleeMagnetismPick {
    /// The nearest actor whose capsule `ray` passes through, with the travel along the ray.
    public static func nearestActor(
        along ray: InteractionRay, actors: [MeleeTarget]
    ) -> (key: ReferenceKey, distance: Float)? {
        let end = ray.origin + ray.direction * ray.maximumDistance
        var best: (key: ReferenceKey, distance: Float)?
        for actor in actors {
            let closest = MeleeHitDetector.closestApproach(
                first: (ray.origin, end), second: actor.segment
            )
            guard simd_distance(closest.onFirst, closest.onSecond) <= actor.capsule.radius
            else { continue }
            let travel = simd_dot(closest.onFirst - ray.origin, ray.direction)
            if travel.isFinite, travel < best?.distance ?? .greatestFiniteMagnitude {
                best = (actor.key, travel)
            }
        }
        return best
    }
}
