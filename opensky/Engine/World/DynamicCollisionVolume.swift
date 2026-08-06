// The collider one dynamic rigid body presents to the solver (issue #193,
// roadmap item 15.2).
//
// A simulated body is always convex here, which is what lets contact generation
// stay a closed-form query rather than a general mesh-mesh intersection. Two
// representations cover every shape the dynamics census found on vanilla
// clutter:
//
// * `radial` is a segment with a radius, so one case covers both a sphere (the
//   segment is a point) and a capsule.
// * `hull` is a point cloud with the outward face planes derived from it, which
//   covers `bhkBoxShape` and `bhkConvexVerticesShape`. A dynamic body whose
//   shape is a triangle soup degrades to the soup's box, because a concave
//   collider has no meaning to this solver and a wrong-shaped body is better
//   than an unsimulated one falling through the floor.
//
// Both answer the same two questions, which together are the whole narrowphase:
// which world points to test against the rest of the world (`contactSamples`),
// and how deep an external sphere sits inside this volume (`penetration`).
//
// Documented in docs/engine/dynamic-bodies.md.

import simd

/// An outward-facing half-space bounding a hull: points inside satisfy
/// `dot(normal, point) <= offset`.
nonisolated struct DynamicCollisionPlane: Equatable, Sendable {
    let normal: SIMD3<Float>
    let offset: Float
}

/// How deep one point sits inside a volume, and which way pushes it out.
nonisolated struct DynamicPenetration: Equatable, Sendable {
    /// Unit vector pointing out of the volume, toward the intruding point.
    let normal: SIMD3<Float>
    /// Positive overlap along `normal`.
    let depth: Float
}

nonisolated enum DynamicCollisionVolume: Sendable {
    /// Sphere when `first == second`, capsule otherwise.
    case radial(first: SIMD3<Float>, second: SIMD3<Float>, radius: Float)
    /// Convex point cloud plus its outward face planes.
    case hull(points: [SIMD3<Float>], planes: [DynamicCollisionPlane])

    /// Planes closer together than this are the same plane, so only one of them
    /// is kept. Engine units, and deliberately loose: a decoded convex hull
    /// repeats a face once per triangle that shares it.
    private static let planeEpsilon: Float = 1e-3

    /// The volume of `geometry`, or nil where it carries nothing solid.
    ///
    /// A triangle soup becomes its own axis-aligned box. That is the one lossy
    /// conversion here and it is deliberate — see the file header.
    static func make(from geometry: NIFCollisionGeometry) -> DynamicCollisionVolume? {
        switch geometry {
        case let .sphere(radius):
            radius > 0 ? .radial(first: .zero, second: .zero, radius: radius) : nil
        case let .capsule(first, second, radius):
            radius > 0 ? .radial(first: first, second: second, radius: radius) : nil
        case let .box(halfExtents):
            box(halfExtents: halfExtents)
        case let .convexVertices(vertices, hullIndices):
            hull(points: vertices, indices: hullIndices)
        case let .triangleSoup(vertices, _):
            ModelBounds.containing(vertices).flatMap {
                box(halfExtents: ($0.max - $0.min) * 0.5, center: ($0.max + $0.min) * 0.5)
            }
        }
    }

    static func box(
        halfExtents: SIMD3<Float>,
        center: SIMD3<Float> = .zero
    ) -> DynamicCollisionVolume? {
        guard halfExtents.min() > 0, halfExtents.max().isFinite else { return nil }
        let corners = CapsuleWorldCollider.boxVertices(halfExtents).map { $0 + center }
        var planes: [DynamicCollisionPlane] = []
        for axis in 0 ..< 3 {
            var normal = SIMD3<Float>.zero
            normal[axis] = 1
            planes.append(DynamicCollisionPlane(
                normal: normal, offset: halfExtents[axis] + center[axis]
            ))
            planes.append(DynamicCollisionPlane(
                normal: -normal, offset: halfExtents[axis] - center[axis]
            ))
        }
        return .hull(points: corners, planes: planes)
    }

    /// A hull from decoded convex points plus the triangle connectivity the NIF
    /// decoder derived for them. Faces whose winding is degenerate are dropped;
    /// a cloud that leaves fewer than four distinct planes cannot bound a
    /// volume and produces nil rather than a hull the solver would read as
    /// infinitely thin.
    static func hull(points: [SIMD3<Float>], indices: [UInt32]) -> DynamicCollisionVolume? {
        guard points.count >= 4 else { return nil }
        let center = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
        var planes: [DynamicCollisionPlane] = []
        for offset in stride(from: 0, to: indices.count - indices.count % 3, by: 3) {
            let triangle = (
                Int(indices[offset]),
                Int(indices[offset + 1]),
                Int(indices[offset + 2])
            )
            guard
                triangle.0 < points.count, triangle.1 < points.count, triangle.2 < points.count,
                let plane = face(
                    points[triangle.0], points[triangle.1], points[triangle.2], center: center
                )
            else { continue }
            guard !planes.contains(where: { $0.isNear(plane, epsilon: planeEpsilon) }) else {
                continue
            }
            planes.append(plane)
        }
        guard planes.count >= 4 else { return nil }
        return .hull(points: points, planes: planes)
    }

    private static func face(
        _ first: SIMD3<Float>,
        _ second: SIMD3<Float>,
        _ third: SIMD3<Float>,
        center: SIMD3<Float>
    ) -> DynamicCollisionPlane? {
        let raw = simd_cross(second - first, third - first)
        guard simd_length_squared(raw) > Float.ulpOfOne, raw.isFiniteVector else { return nil }
        var normal = simd_normalize(raw)
        // The decoder's derived hull connectivity does not promise a consistent
        // winding, so the hull's own centroid decides which side is outside.
        if simd_dot(normal, first - center) < 0 {
            normal = -normal
        }
        return DynamicCollisionPlane(normal: normal, offset: simd_dot(normal, first))
    }

    /// World-space points the solver tests against everything else, given the
    /// body's pose. A hull reports its vertices; a radial volume reports its two
    /// segment ends, whose skin radius carries the rest of the shape.
    func contactSamples(position: SIMD3<Float>, orientation: simd_quatf) -> [SIMD3<Float>] {
        switch self {
        case let .radial(first, second, _):
            first == second
                ? [position + orientation.act(first)]
                : [position + orientation.act(first), position + orientation.act(second)]
        case let .hull(points, _):
            points.map { position + orientation.act($0) }
        }
    }

    /// The skin every contact sample carries. Zero for a hull, whose vertices
    /// are the surface itself.
    var skinRadius: Float {
        switch self {
        case let .radial(_, _, radius): radius
        case .hull: 0
        }
    }

    /// How deep a sphere of `radius` centred on `point` — both in this volume's
    /// own local frame — sits inside it, or nil where it does not touch.
    ///
    /// The hull answer is the standard convex-vs-sphere test: the least
    /// separated face plane decides, so a point strictly inside every plane is
    /// pushed out along the face it is nearest to.
    func penetration(of point: SIMD3<Float>, radius: Float) -> DynamicPenetration? {
        switch self {
        case let .radial(first, second, volumeRadius):
            let closest = DynamicCollisionMath.closestPoint(onSegment: (first, second), to: point)
            let delta = point - closest
            let distance = simd_length(delta)
            let combined = volumeRadius + radius
            guard distance < combined else { return nil }
            let normal = distance > Float.ulpOfOne
                ? delta / distance
                : DynamicCollisionMath.fallbackNormal
            return DynamicPenetration(normal: normal, depth: combined - distance)
        case let .hull(_, planes):
            var bestNormal = DynamicCollisionMath.fallbackNormal
            var leastSeparation = -Float.greatestFiniteMagnitude
            for plane in planes {
                let separation = simd_dot(plane.normal, point) - plane.offset
                if separation > leastSeparation {
                    leastSeparation = separation
                    bestNormal = plane.normal
                }
            }
            guard leastSeparation < radius else { return nil }
            return DynamicPenetration(normal: bestNormal, depth: radius - leastSeparation)
        }
    }

    /// Local-space AABB, skin included.
    var localBounds: ModelBounds {
        switch self {
        case let .radial(first, second, radius):
            let extent = SIMD3<Float>(repeating: radius)
            return ModelBounds(
                min: simd_min(first, second) - extent,
                max: simd_max(first, second) + extent
            )
        case let .hull(points, _):
            return ModelBounds.containing(points) ?? ModelBounds(min: .zero, max: .zero)
        }
    }

    /// Distance from the local origin to the farthest surface point — the
    /// radius of the sphere a rotating body can never leave, which is what the
    /// broadphase inflates its query box by.
    var boundingRadius: Float {
        switch self {
        case let .radial(first, second, radius):
            max(simd_length(first), simd_length(second)) + radius
        case let .hull(points, _):
            points.reduce(0) { max($0, simd_length($1)) }
        }
    }

    /// The same volume with every point moved by `offset`, used to re-express a
    /// body's shapes relative to its centre of mass.
    func translated(by offset: SIMD3<Float>) -> DynamicCollisionVolume {
        switch self {
        case let .radial(first, second, radius):
            .radial(first: first + offset, second: second + offset, radius: radius)
        case let .hull(points, planes):
            .hull(
                points: points.map { $0 + offset },
                planes: planes.map {
                    DynamicCollisionPlane(
                        normal: $0.normal,
                        offset: $0.offset + simd_dot($0.normal, offset)
                    )
                }
            )
        }
    }

    /// The same volume placed by an affine transform. Rotation and translation
    /// apply to points; the radius of a radial volume takes the transform's
    /// largest axis scale, matching how the static narrowphase scales a placed
    /// sphere or capsule.
    func transformed(by matrix: float4x4) -> DynamicCollisionVolume? {
        let scale = DynamicCollisionMath.maximumScale(of: matrix)
        switch self {
        case let .radial(first, second, radius):
            return .radial(
                first: DynamicCollisionMath.transform(first, by: matrix),
                second: DynamicCollisionMath.transform(second, by: matrix),
                radius: radius * scale
            )
        case let .hull(points, planes):
            let moved = points.map { DynamicCollisionMath.transform($0, by: matrix) }
            let center = moved.reduce(SIMD3<Float>.zero, +) / Float(max(moved.count, 1))
            let rotated = planes.compactMap { plane -> DynamicCollisionPlane? in
                let direction = DynamicCollisionMath.transform(plane.normal, by: matrix)
                    - DynamicCollisionMath.transform(.zero, by: matrix)
                guard simd_length_squared(direction) > Float.ulpOfOne else { return nil }
                let normal = simd_normalize(direction)
                // The plane's own offset does not survive a non-uniform scale,
                // so it is re-measured against the transformed points instead.
                let offset = moved.reduce(-Float.greatestFiniteMagnitude) {
                    max($0, simd_dot(normal, $1))
                }
                return simd_dot(normal, center) < offset
                    ? DynamicCollisionPlane(normal: normal, offset: offset)
                    : nil
            }
            return rotated.count >= 4 ? .hull(points: moved, planes: rotated) : nil
        }
    }
}

nonisolated extension DynamicCollisionPlane {
    func isNear(_ other: DynamicCollisionPlane, epsilon: Float) -> Bool {
        simd_length(normal - other.normal) <= epsilon && abs(offset - other.offset) <= epsilon
    }
}

/// Small geometric helpers the dynamic solver shares. Kept beside the volume
/// rather than reached for from `CapsuleWorldCollider`, whose equivalents are
/// private to the player-capsule narrowphase.
nonisolated enum DynamicCollisionMath {
    /// The direction a degenerate contact is pushed along when the geometry
    /// gives no usable one: straight up, which is the harmless answer for a
    /// body that has ended up exactly on an obstacle's axis.
    static let fallbackNormal = SIMD3<Float>(0, 0, 1)

    static func closestPoint(
        onSegment segment: (SIMD3<Float>, SIMD3<Float>),
        to point: SIMD3<Float>
    ) -> SIMD3<Float> {
        let delta = segment.1 - segment.0
        let lengthSquared = simd_length_squared(delta)
        guard lengthSquared > Float.ulpOfOne else { return segment.0 }
        let time = max(0, min(1, simd_dot(point - segment.0, delta) / lengthSquared))
        return segment.0 + delta * time
    }

    static func transform(_ point: SIMD3<Float>, by matrix: float4x4) -> SIMD3<Float> {
        let transformed = matrix * SIMD4<Float>(point, 1)
        return SIMD3(transformed.x, transformed.y, transformed.z)
    }

    static func maximumScale(of matrix: float4x4) -> Float {
        max(
            simd_length(SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)),
            simd_length(SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)),
            simd_length(SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
        )
    }
}

nonisolated extension SIMD3 where Scalar == Float {
    var isFiniteVector: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}
