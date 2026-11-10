// The faces and edges of a convex hull, found once per body from its points and
// planes, so two hulls can meet face to face or edge to edge.
// See docs/engine/dynamic-narrowphase.md#body-against-body.

import simd

/// One hull's polygons and edge directions, in the same local space as its points.
nonisolated public struct DynamicHullTopology: Sendable {
    /// Per plane of the hull, the indices of the points on it, wound counter-clockwise
    /// about the plane's normal. A plane with fewer than three points has an empty face.
    let faces: [[Int]]
    /// Each edge as a pair of point indices, once.
    let edges: [SIMD2<Int32>]
    /// Unit edge directions with the parallel ones merged: a box has three.
    let edgeDirections: [SIMD3<Float>]

    /// How far a point may sit from a plane and still be on its face, as a share of
    /// the hull's size. A decoded hull's points are rounded.
    private static let onPlaneShare: Float = 1e-3
    /// Two directions this close to parallel are one direction.
    private static let parallelCosine: Float = 0.9995

    init?(points: [SIMD3<Float>], planes: [DynamicCollisionPlane]) {
        guard points.count >= 4, planes.count >= 4 else { return nil }
        let low = points.reduce(points[0], simd_min)
        let high = points.reduce(points[0], simd_max)
        let tolerance = max(simd_length(high - low) * Self.onPlaneShare, 1e-3)
        var faces: [[Int]] = []
        var edgeSet = Set<SIMD2<Int32>>()
        var edges: [SIMD2<Int32>] = []
        for plane in planes {
            let face = Self.face(on: plane, points: points, tolerance: tolerance)
            faces.append(face)
            guard face.count >= 3 else { continue }
            for index in face.indices {
                let start = Int32(face[index])
                let end = Int32(face[(index + 1) % face.count])
                let key = SIMD2(min(start, end), max(start, end))
                if edgeSet.insert(key).inserted {
                    edges.append(key)
                }
            }
        }
        guard faces.contains(where: { $0.count >= 3 }) else { return nil }
        self.faces = faces
        self.edges = edges
        edgeDirections = Self.directions(of: edges, points: points)
    }

    private static func face(
        on plane: DynamicCollisionPlane, points: [SIMD3<Float>], tolerance: Float
    ) -> [Int] {
        var members: [Int] = []
        for (index, point) in points.enumerated()
            where abs(simd_dot(plane.normal, point) - plane.offset) <= tolerance
            && !members.contains(where: { simd_distance(points[$0], point) <= tolerance })
        {
            members.append(index)
        }
        guard members.count >= 3 else { return members }
        let centre = members.reduce(SIMD3<Float>.zero) { $0 + points[$1] } / Float(members.count)
        let reference = abs(plane.normal.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3(0, 1, 0)
        let across = simd_normalize(simd_cross(plane.normal, reference))
        let up = simd_cross(plane.normal, across)
        return members.sorted { first, second in
            let lhs = points[first] - centre
            let rhs = points[second] - centre
            return atan2(simd_dot(lhs, up), simd_dot(lhs, across))
                < atan2(simd_dot(rhs, up), simd_dot(rhs, across))
        }
    }

    private static func directions(
        of edges: [SIMD2<Int32>], points: [SIMD3<Float>]
    ) -> [SIMD3<Float>] {
        var directions: [SIMD3<Float>] = []
        for edge in edges {
            let delta = points[Int(edge.y)] - points[Int(edge.x)]
            guard simd_length_squared(delta) > Float.ulpOfOne else { continue }
            let direction = simd_normalize(delta)
            if !directions.contains(where: { abs(simd_dot($0, direction)) >= parallelCosine }) {
                directions.append(direction)
            }
        }
        return directions
    }
}

nonisolated extension DynamicCollisionVolume {
    /// The faces and edges of a hull; nil for a radial volume.
    public var hullTopology: DynamicHullTopology? {
        guard case let .hull(points, planes) = self else { return nil }
        return DynamicHullTopology(points: points, planes: planes)
    }
}
