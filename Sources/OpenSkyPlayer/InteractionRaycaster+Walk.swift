// Ray casts that walk each resident collision tree along the ray, instead of testing
// every shape in the ray's bounding box. The result is the one `nearestHit(ray:shapes:)`
// gives for the same shapes in the same order.

import OpenSkyPhysics
import OpenSkyWorldInterface

nonisolated extension InteractionRaycaster {
    /// The nearest hit over the trees in `sets`, then the loose `shapes`, which are
    /// tested one by one. Ties break as in `nearestHit(ray:shapes:)`.
    public static func nearestHit(
        ray: InteractionRay,
        sets: [StaticCollisionSet],
        shapes: [StaticCollisionShape]
    ) -> InteractionRayHit? {
        var found: [OrderedHit] = []
        var nearest = Float.infinity
        for (setIndex, set) in sets.enumerated() {
            set.walk(along: segment(ray)) { shape, element in
                if let hit = hit(ray: ray, shape: shape) {
                    found.append(OrderedHit(set: setIndex, element: element, hit: hit))
                    nearest = min(nearest, hit.distance)
                }
                // A shape just past the nearest hit can still win the tie-break.
                return nearest + epsilon
            }
        }
        found.sort { ($0.set, $0.element) < ($1.set, $1.element) }
        let loose = shapes.compactMap { hit(ray: ray, shape: $0) }
        return Self.nearest(of: found.map(\.hit) + loose)
    }

    /// Whether anything in `sets` or `shapes` blocks the ray. Stops at the first hit.
    public static func hasHit(
        ray: InteractionRay,
        sets: [StaticCollisionSet],
        shapes: [StaticCollisionShape]
    ) -> Bool {
        var blocked = false
        for set in sets where !blocked {
            set.walk(along: segment(ray)) { shape, _ in
                blocked = hit(ray: ray, shape: shape) != nil
                return blocked ? -1 : .infinity
            }
        }
        return blocked || shapes.contains { hit(ray: ray, shape: $0) != nil }
    }

    private static func segment(_ ray: InteractionRay) -> RaySegment {
        RaySegment(
            origin: ray.origin, direction: ray.direction, maximumDistance: ray.maximumDistance
        )
    }
}

/// A tree hit with where its shape sits, so hits fold in the box query's order.
nonisolated private struct OrderedHit {
    let set: Int
    let element: Int
    let hit: InteractionRayHit
}
