// Contacts between two convex hulls by separating axes and face clipping: a box
// resting on a box touches at up to four points, and two crossed edges touch at
// their closest points. See docs/engine/dynamic-narrowphase.md#body-against-body.

import simd

/// A hull at a body's pose, in world space.
nonisolated struct DynamicPosedHull {
    let points: [SIMD3<Float>]
    let planes: [DynamicCollisionPlane]
    let topology: DynamicHullTopology
    let edgeDirections: [SIMD3<Float>]
    let centre: SIMD3<Float>

    init(
        points local: [SIMD3<Float>], planes localPlanes: [DynamicCollisionPlane],
        topology: DynamicHullTopology, position: SIMD3<Float>, orientation: simd_quatf
    ) {
        points = local.map { position + orientation.act($0) }
        planes = localPlanes.map { plane in
            let normal = orientation.act(plane.normal)
            return DynamicCollisionPlane(
                normal: normal, offset: plane.offset + simd_dot(normal, position)
            )
        }
        self.topology = topology
        edgeDirections = topology.edgeDirections.map { orientation.act($0) }
        centre = points.reduce(SIMD3<Float>.zero, +) / Float(max(points.count, 1))
    }

    func highest(along direction: SIMD3<Float>) -> Float {
        points.reduce(-Float.greatestFiniteMagnitude) { max($0, simd_dot(direction, $1)) }
    }

    func lowest(along direction: SIMD3<Float>) -> Float {
        points.reduce(Float.greatestFiniteMagnitude) { min($0, simd_dot(direction, $1)) }
    }

    func polygon(_ face: Int) -> [SIMD3<Float>] {
        topology.faces[face].map { points[$0] }
    }
}

/// The touch between two hulls: the reference hull's outward normal and points on its
/// surface, each with how far the other hull's surface is above it there.
nonisolated struct DynamicHullManifold {
    /// True when the first hull gives the normal.
    let firstIsReference: Bool
    let normal: SIMD3<Float>
    let points: [(position: SIMD3<Float>, separation: Float)]
}

nonisolated enum DynamicConvexManifold {
    /// An edge axis wins only when it separates this much more than the best face, in
    /// engine units. Faces give steadier contacts, so a near tie goes to a face.
    static let edgePreference: Float = 0.05
    static let maximumPoints = 4

    private enum Axis {
        case firstFace(Int)
        case secondFace(Int)
        case edges(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)
    }

    /// Nil when an axis separates the hulls by more than `margin`.
    static func manifold(
        first: DynamicPosedHull, second: DynamicPosedHull, margin: Float
    ) -> DynamicHullManifold? {
        guard let (axis, separation) = bestAxis(first: first, second: second, margin: margin)
        else { return nil }
        switch axis {
        case let .firstFace(face):
            return clipped(reference: first, face: face, incident: second, margin: margin)
                .map { DynamicHullManifold(firstIsReference: true, normal: $0.0, points: $0.1) }
        case let .secondFace(face):
            return clipped(reference: second, face: face, incident: first, margin: margin)
                .map { DynamicHullManifold(firstIsReference: false, normal: $0.0, points: $0.1) }
        case let .edges(axis, firstEdge, secondEdge):
            let point = edgeContact(
                first: first, second: second, axis: axis, directions: (firstEdge, secondEdge)
            )
            return DynamicHullManifold(
                firstIsReference: true, normal: axis, points: [(point, separation)]
            )
        }
    }

    private static func bestAxis(
        first: DynamicPosedHull, second: DynamicPosedHull, margin: Float
    ) -> (Axis, Float)? {
        var best: (Axis, Float)?
        for (index, plane) in first.planes.enumerated()
            where first.topology.faces[index].count >= 3
        {
            let separation = second.lowest(along: plane.normal) - plane.offset
            guard separation <= margin else { return nil }
            if separation > best?.1 ?? -.greatestFiniteMagnitude {
                best = (.firstFace(index), separation)
            }
        }
        for (index, plane) in second.planes.enumerated()
            where second.topology.faces[index].count >= 3
        {
            let separation = first.lowest(along: plane.normal) - plane.offset
            guard separation <= margin else { return nil }
            if separation > best?.1 ?? -.greatestFiniteMagnitude {
                best = (.secondFace(index), separation)
            }
        }
        guard
            let face = best,
            let edge = bestEdgeAxis(first: first, second: second, margin: margin)
        else {
            return nil
        }
        return edge.1 > face.1 + edgePreference ? edge : face
    }

    /// The edge pair whose cross product separates most. The axis points from `first`
    /// toward `second`. A separating pair returns nil through the caller's margin test.
    private static func bestEdgeAxis(
        first: DynamicPosedHull, second: DynamicPosedHull, margin: Float
    ) -> (Axis, Float)? {
        var best: (Axis, Float) = (.firstFace(0), -.greatestFiniteMagnitude)
        let towardSecond = second.centre - first.centre
        for firstEdge in first.edgeDirections {
            for secondEdge in second.edgeDirections {
                let cross = simd_cross(firstEdge, secondEdge)
                let length = simd_length(cross)
                guard length > 1e-3 else { continue }
                var axis = cross / length
                if simd_dot(axis, towardSecond) < 0 {
                    axis = -axis
                }
                let separation = second.lowest(along: axis) - first.highest(along: axis)
                guard separation <= margin else { return nil }
                if separation > best.1 {
                    best = (.edges(axis, firstEdge, secondEdge), separation)
                }
            }
        }
        return best
    }

    /// The incident hull's most opposed face, clipped to the reference face's sides.
    private static func clipped(
        reference: DynamicPosedHull, face: Int, incident: DynamicPosedHull, margin: Float
    ) -> (SIMD3<Float>, [(position: SIMD3<Float>, separation: Float)])? {
        let plane = reference.planes[face]
        var incidentFace: Int?
        var mostOpposed = Float.greatestFiniteMagnitude
        for (index, candidate) in incident.planes.enumerated()
            where incident.topology.faces[index].count >= 3
        {
            let alignment = simd_dot(candidate.normal, plane.normal)
            if alignment < mostOpposed {
                mostOpposed = alignment
                incidentFace = index
            }
        }
        guard let incidentFace else { return nil }
        let referencePolygon = reference.polygon(face)
        var polygon = incident.polygon(incidentFace)
        let faceCentre = referencePolygon.reduce(SIMD3<Float>.zero, +)
            / Float(referencePolygon.count)
        for index in referencePolygon.indices {
            let start = referencePolygon[index]
            let end = referencePolygon[(index + 1) % referencePolygon.count]
            var side = simd_cross(end - start, plane.normal)
            guard simd_length_squared(side) > Float.ulpOfOne else { continue }
            side = simd_normalize(side)
            if simd_dot(side, start - faceCentre) < 0 {
                side = -side
            }
            polygon = clip(polygon, normal: side, offset: simd_dot(side, start))
        }
        let points = polygon.compactMap { point -> (position: SIMD3<Float>, separation: Float)? in
            let separation = simd_dot(plane.normal, point) - plane.offset
            return separation <= margin ? (point - plane.normal * separation, separation) : nil
        }
        return points.isEmpty ? nil : (plane.normal, reduced(points))
    }

    /// Sutherland-Hodgman: the part of `polygon` where `dot(normal, point) <= offset`.
    static func clip(
        _ polygon: [SIMD3<Float>], normal: SIMD3<Float>, offset: Float
    ) -> [SIMD3<Float>] {
        guard !polygon.isEmpty else { return [] }
        var result: [SIMD3<Float>] = []
        for index in polygon.indices {
            let current = polygon[index]
            let next = polygon[(index + 1) % polygon.count]
            let currentDistance = simd_dot(normal, current) - offset
            let nextDistance = simd_dot(normal, next) - offset
            if currentDistance <= 0 {
                result.append(current)
            }
            if (currentDistance < 0) != (nextDistance < 0), currentDistance != nextDistance {
                let share = currentDistance / (currentDistance - nextDistance)
                result.append(current + (next - current) * share)
            }
        }
        return result
    }

    /// At most four points: the deepest, the one farthest from it, then the two that
    /// spread them most. They hold a resting box as well as the whole polygon does.
    static func reduced(
        _ points: [(position: SIMD3<Float>, separation: Float)]
    ) -> [(position: SIMD3<Float>, separation: Float)] {
        guard points.count > maximumPoints else { return points }
        var chosen = [points.indices.min { points[$0].separation < points[$1].separation } ?? 0]
        func farthest(_ score: (SIMD3<Float>) -> Float) -> Int? {
            points.indices.filter { !chosen.contains($0) }
                .max { score(points[$0].position) < score(points[$1].position) }
        }
        let anchor = points[chosen[0]].position
        if let next = farthest({ simd_distance_squared($0, anchor) }) {
            chosen.append(next)
        }
        let line = (anchor, points[chosen[1]].position)
        if let next = farthest({ simd_length(simd_cross(line.1 - line.0, $0 - line.0)) }) {
            chosen.append(next)
        }
        let triangle = chosen.map { points[$0].position }
        if let next = farthest({ point in triangle.reduce(0) { $0 + simd_distance(point, $1) } }) {
            chosen.append(next)
        }
        return chosen.map { points[$0] }
    }

    /// The point on `first`'s supporting edge closest to `second`'s.
    private static func edgeContact(
        first: DynamicPosedHull, second: DynamicPosedHull, axis: SIMD3<Float>,
        directions: (SIMD3<Float>, SIMD3<Float>)
    ) -> SIMD3<Float> {
        let firstEdge = supportingEdge(of: first, direction: directions.0, along: axis)
        let secondEdge = supportingEdge(of: second, direction: directions.1, along: -axis)
        guard let firstEdge, let secondEdge else { return (first.centre + second.centre) * 0.5 }
        return DynamicCollisionMath.closestPoints(firstEdge, secondEdge).0
    }

    private static func supportingEdge(
        of hull: DynamicPosedHull, direction: SIMD3<Float>, along axis: SIMD3<Float>
    ) -> (SIMD3<Float>, SIMD3<Float>)? {
        var best: (SIMD3<Float>, SIMD3<Float>)?
        var highest = -Float.greatestFiniteMagnitude
        for edge in hull.topology.edges {
            let start = hull.points[Int(edge.x)]
            let end = hull.points[Int(edge.y)]
            let delta = end - start
            guard
                simd_length_squared(delta) > Float.ulpOfOne,
                abs(simd_dot(simd_normalize(delta), direction)) > 0.999
            else { continue }
            let height = simd_dot(axis, start + end)
            if height > highest {
                highest = height
                best = (start, end)
            }
        }
        return best
    }
}

nonisolated extension DynamicCollisionMath {
    /// The closest points of two segments, first on `first`, then on `second`.
    static func closestPoints(
        _ first: (SIMD3<Float>, SIMD3<Float>), _ second: (SIMD3<Float>, SIMD3<Float>)
    ) -> (SIMD3<Float>, SIMD3<Float>) {
        let firstDelta = first.1 - first.0
        let secondDelta = second.1 - second.0
        let between = first.0 - second.0
        let firstLength = simd_length_squared(firstDelta)
        let secondLength = simd_length_squared(secondDelta)
        let alongSecond = simd_dot(secondDelta, between)
        guard firstLength > Float.ulpOfOne || secondLength > Float.ulpOfOne else {
            return (first.0, second.0)
        }
        guard firstLength > Float.ulpOfOne else {
            let time = min(max(alongSecond / secondLength, 0), 1)
            return (first.0, second.0 + secondDelta * time)
        }
        let alongFirst = simd_dot(firstDelta, between)
        guard secondLength > Float.ulpOfOne else {
            let time = min(max(-alongFirst / firstLength, 0), 1)
            return (first.0 + firstDelta * time, second.0)
        }
        let mixed = simd_dot(firstDelta, secondDelta)
        let denominator = firstLength * secondLength - mixed * mixed
        var firstTime = denominator > Float.ulpOfOne
            ? min(max((mixed * alongSecond - alongFirst * secondLength) / denominator, 0), 1)
            : 0
        var secondTime = (mixed * firstTime + alongSecond) / secondLength
        if secondTime < 0 {
            secondTime = 0
            firstTime = min(max(-alongFirst / firstLength, 0), 1)
        } else if secondTime > 1 {
            secondTime = 1
            firstTime = min(max((mixed - alongFirst) / firstLength, 0), 1)
        }
        return (first.0 + firstDelta * firstTime, second.0 + secondDelta * secondTime)
    }
}
