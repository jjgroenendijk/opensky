// A body's contacts on one surface carry its weight together, at the point under
// its centre of mass. Solving the corners one by one let the first corner take
// the whole load each step, which spun a goblet off its foot.
// See docs/engine/dynamic-narrowphase.md#contact-patches.

import simd

nonisolated enum DynamicContactPatch {
    /// Two contact normals closer than this share a surface.
    static let sameSurfaceCosine: Float = 0.98

    /// One support contact per group of two or more contacts that share a body, an
    /// other body, and a normal. A single contact needs no patch.
    static func supports(
        of contacts: [DynamicContact], bodies: [DynamicBody]
    ) -> [DynamicContact] {
        var groups: [[Int]] = []
        for (index, contact) in contacts.enumerated() {
            let match = groups.firstIndex { group in
                let first = contacts[group[0]]
                return first.body == contact.body && first.other == contact.other
                    && simd_dot(first.normal, contact.normal) >= sameSurfaceCosine
            }
            if let match {
                groups[match].append(index)
            } else {
                groups.append([index])
            }
        }
        return groups.filter { $0.count > 1 }.map { group in
            support(
                of: group.map { contacts[$0] },
                centre: bodies[contacts[group[0]].body].position
            )
        }
    }

    private static func support(
        of contacts: [DynamicContact], centre: SIMD3<Float>
    ) -> DynamicContact {
        let normal = simd_normalize(contacts.reduce(SIMD3<Float>.zero) { $0 + $1.normal })
        let origin = contacts[0].point
        let reference = abs(normal.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3(0, 1, 0)
        let across = simd_normalize(simd_cross(normal, reference))
        let along = simd_cross(normal, across)
        let flat = contacts.map {
            SIMD2(simd_dot($0.point - origin, across), simd_dot($0.point - origin, along))
        }
        let target = SIMD2(simd_dot(centre - origin, across), simd_dot(centre - origin, along))
        let spot = closest(to: target, inHullOf: flat)
        let first = contacts[0]
        return DynamicContact(
            body: first.body,
            other: first.other,
            point: origin + across * spot.x + along * spot.y,
            normal: normal,
            depth: contacts.reduce(0) { max($0, $1.depth) },
            friction: first.friction,
            restitution: first.restitution,
            surfaceMaterial: first.surfaceMaterial
        )
    }

    /// `target` itself when it lies inside the convex hull of `points`, else the hull's
    /// nearest boundary point.
    static func closest(to target: SIMD2<Float>, inHullOf points: [SIMD2<Float>]) -> SIMD2<Float> {
        let hull = convexHull(points)
        guard hull.count > 1 else { return hull.first ?? target }
        var inside = hull.count > 2
        var best = hull[0]
        var bestDistance = Float.greatestFiniteMagnitude
        for index in hull.indices {
            let start = hull[index]
            let end = hull[(index + 1) % hull.count]
            let edge = end - start
            if simd_cross(SIMD3(edge, 0), SIMD3(target - start, 0)).z < 0 {
                inside = false
            }
            let length = simd_length_squared(edge)
            let time = length > Float.ulpOfOne
                ? min(max(simd_dot(target - start, edge) / length, 0), 1)
                : 0
            let point = start + edge * time
            let distance = simd_distance_squared(point, target)
            if distance < bestDistance {
                bestDistance = distance
                best = point
            }
        }
        return inside ? target : best
    }

    /// Andrew's monotone chain, counter-clockwise, without collinear points.
    static func convexHull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let sorted = points.sorted { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }
        guard sorted.count > 2 else { return sorted }
        func turn(_ origin: SIMD2<Float>, _ first: SIMD2<Float>, _ second: SIMD2<Float>) -> Float {
            simd_cross(SIMD3(first - origin, 0), SIMD3(second - origin, 0)).z
        }
        var lower: [SIMD2<Float>] = []
        for point in sorted {
            while
                lower.count >= 2,
                turn(lower[lower.count - 2], lower[lower.count - 1], point) <= 0
            {
                lower.removeLast()
            }
            lower.append(point)
        }
        var upper: [SIMD2<Float>] = []
        for point in sorted.reversed() {
            while
                upper.count >= 2,
                turn(upper[upper.count - 2], upper[upper.count - 1], point) <= 0
            {
                upper.removeLast()
            }
            upper.append(point)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }
}
