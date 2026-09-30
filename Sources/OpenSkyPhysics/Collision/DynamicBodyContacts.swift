// Narrowphase for dynamic rigid bodies: contacts with the static world and
// between two dynamic bodies. Each contact is a sample point plus a skin radius
// tested against the other surface. `recoveryDepth` bounds how far behind a
// surface a contact is still believed. See docs/engine/dynamic-narrowphase.md.

import OpenSkyFormatsMesh
import simd

/// Placed triangle geometry a penetration query runs against, bundled so the
/// query stays inside the strict parameter cap.
nonisolated public struct PlacedTriangleSoup: Sendable {
    public let vertices: [SIMD3<Float>]
    public let indices: [UInt32]
    public let transform: float4x4
}

/// One body's contact samples in a placed shape's local space, with the box that
/// bounds them at full reach. Testing each triangle against the box first turns
/// many rejects into one. `recovery` sizes the box; see
/// `DynamicBodyContacts.recoveryDepth(of:)`.
nonisolated public struct DynamicLocalSamples: Sendable {
    public let points: [SIMD3<Float>]
    /// Each sample's skin, with `contactMargin` added and the shape's scale
    /// divided out, so every length below is in the shape's own units.
    public let radii: [Float]
    /// How this shape's triangles are turned into surface normals, in the same
    /// local space the samples are in.
    public let orientation: DynamicSurfaceOrientation
    /// `recoveryDepth` in the shape's units.
    public let recovery: Float
    /// Sample AABB grown by the largest sample reach.
    public let lower: SIMD3<Float>
    public let upper: SIMD3<Float>

    /// Nil where the shape's placement will not invert or a sample does not
    /// survive the transform, which leaves the shape contributing no contact
    /// rather than a nonsense one.
    public init?(
        samples: [(point: SIMD3<Float>, radius: Float)],
        shape: StaticCollisionShape,
        recovery worldRecovery: Float
    ) {
        let determinant = simd_determinant(shape.transform)
        let scale = DynamicCollisionMath.maximumScale(of: shape.transform)
        guard
            determinant.isFinite, abs(determinant) > 1e-9, scale > Float.ulpOfOne,
            !samples.isEmpty
        else { return nil }
        let inverse = shape.transform.inverse
        points = samples.map { DynamicCollisionMath.transform($0.point, by: inverse) }
        radii = samples.map { ($0.radius + DynamicBodyContacts.contactMargin) / scale }
        orientation = DynamicSurfaceOrientation.of(shape.geometry)
        recovery = worldRecovery / scale
        guard points.allSatisfy(\.isFiniteVector) else { return nil }
        let reach = (radii.max() ?? 0) + recovery
        var low = points[0]
        var high = points[0]
        for point in points.dropFirst() {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        lower = low - SIMD3(repeating: reach)
        upper = high + SIMD3(repeating: reach)
    }
}

/// One body with its contact samples already taken, so the sampling is paid for
/// once per substep rather than once per query.
nonisolated public struct DynamicBodySamples: Sendable {
    public let body: DynamicBody
    /// The body's index in the solver's array.
    public let index: Int
    public let samples: [(point: SIMD3<Float>, radius: Float)]
}

/// The friction and restitution a pair of bodies contributes to its contacts.
nonisolated public struct DynamicContactMaterial: Sendable {
    public let friction: Float
    public let restitution: Float
}

/// One resolved touch. `normal` always points away from the obstacle and toward
/// `body`, so a positive normal impulse separates them.
nonisolated public struct DynamicContact: Sendable {
    /// Index into the solver's body array.
    public let body: Int
    /// The other dynamic body, or nil for a contact against static geometry.
    public let other: Int?
    /// World-space contact point.
    public let point: SIMD3<Float>
    public let normal: SIMD3<Float>
    /// Positive overlap along `normal`.
    public let depth: Float
    public let friction: Float
    public let restitution: Float
}

nonisolated public enum DynamicBodyContacts: Sendable {
    /// Collision margin every contact sample carries on top of its volume's own
    /// skin. A hull vertex has no skin of its own, so without a margin a resting
    /// box would generate contacts only while already interpenetrating and would
    /// jitter between touching and free. Engine units.
    public static let contactMargin: Float = 1.5

    /// How far behind a surface a contact is still believed, in engine units.
    /// Past it the sample is taken to belong to different geometry rather than
    /// to a deep penetration of this one.
    public static let recoveryDepth: Float = 48

    /// The same bound for one body: the smaller of `recoveryDepth` and the body's own
    /// reach. Scaling it down for small clutter was the largest saving in the step.
    public static func recoveryDepth(of body: DynamicBody) -> Float {
        min(recoveryDepth, max(contactMargin * 4, body.definition.boundingRadius))
    }

    /// Contacts between `body` and the placed static shapes `shapes`.
    ///
    /// Shapes are visited in the order the broadphase returned them, which is
    /// source-shape order and therefore stable, so the contact list is
    /// deterministic for a given pose.
    public static func staticContacts(
        body: DynamicBody,
        index: Int,
        samples: [(point: SIMD3<Float>, radius: Float)],
        shapes: [StaticCollisionShape]
    ) -> [DynamicContact] {
        var result: [DynamicContact] = []
        for shape in shapes {
            // A body's samples are its hull corners, so the same shape is asked
            // about eight times over. Testing them together lets a placed
            // triangle be built once per shape rather than once per sample,
            // which is the difference between an affordable step and an
            // unaffordable one on real interior geometry.
            for (sample, hit) in penetrations(
                of: samples, shape: shape, recovery: recoveryDepth(of: body)
            ) {
                let radius = sample.radius + contactMargin
                result.append(DynamicContact(
                    body: index,
                    other: nil,
                    point: sample.point - hit.normal * (radius - hit.depth),
                    normal: hit.normal,
                    depth: hit.depth,
                    friction: body.definition.friction,
                    restitution: body.definition.restitution
                ))
            }
        }
        return result
    }

    /// The deepest penetration of each sample into one placed shape, in sample order.
    /// The work runs in the shape's local space: moving a few samples through one
    /// inverse matrix is cheaper than moving every triangle. The placement is rigid
    /// times uniform scale, so lengths convert back exactly.
    private static func penetrations(
        of samples: [(point: SIMD3<Float>, radius: Float)],
        shape: StaticCollisionShape,
        recovery: Float
    ) -> [(sample: (point: SIMD3<Float>, radius: Float), hit: DynamicPenetration)] {
        var deepest = [DynamicPenetration?](repeating: nil, count: samples.count)
        switch shape.geometry {
        case let .triangleSoup(vertices, indices),
             let .convexVertices(vertices, indices):
            guard
                let local = DynamicLocalSamples(
                    samples: samples, shape: shape, recovery: recovery
                )
            else { break }
            accumulate(
                soup: (vertices: vertices, indices: indices),
                against: local,
                shape: shape,
                into: &deepest
            )
        case let .box(halfExtents):
            guard
                let local = DynamicLocalSamples(
                    samples: samples, shape: shape, recovery: recovery
                )
            else { break }
            accumulate(
                soup: (
                    vertices: CapsuleWorldCollider.boxVertices(halfExtents),
                    indices: CapsuleWorldCollider.boxIndices
                ),
                against: local,
                shape: shape,
                into: &deepest
            )
        case .sphere, .capsule:
            for (index, sample) in samples.enumerated() {
                deepest[index] = penetration(
                    of: sample.point,
                    radius: sample.radius + contactMargin,
                    shape: shape
                )
            }
        }
        return samples.indices.compactMap { index in
            deepest[index].map { (sample: samples[index], hit: $0) }
        }
    }

    /// One pass over a shape's own triangles, deepening every sample's answer as
    /// it goes. The samples arrive already in the shape's space; the answers are
    /// moved back to the world before they are returned.
    private static func accumulate(
        soup: (vertices: [SIMD3<Float>], indices: [UInt32]),
        against local: DynamicLocalSamples,
        shape: StaticCollisionShape,
        into deepest: inout [DynamicPenetration?]
    ) {
        let vertices = soup.vertices
        let indices = soup.indices
        let end = indices.count - indices.count % 3
        var localNearest = [(distance: Float, penetration: DynamicPenetration?)?](
            repeating: nil, count: local.points.count
        )
        for offset in stride(from: 0, to: end, by: 3) {
            let first = Int(indices[offset])
            let second = Int(indices[offset + 1])
            let third = Int(indices[offset + 2])
            guard first < vertices.count, second < vertices.count, third < vertices.count else {
                continue
            }
            let corners = (vertices[first], vertices[second], vertices[third])
            // One reject for the whole body before the triangle is prepared at
            // all. Most of a room-sized soup is nowhere near a single piece of
            // clutter, and this is the test that decides whether anything else
            // about the triangle is paid for.
            let low = simd_min(simd_min(corners.0, corners.1), corners.2)
            let high = simd_max(simd_max(corners.0, corners.1), corners.2)
            guard
                all(low .<= local.upper), all(high .>= local.lower),
                let surface = DynamicSurfaceTriangle(
                    CollisionTriangle(first: corners.0, second: corners.1, third: corners.2),
                    orientation: local.orientation
                )
            else { continue }
            accumulate(surface: surface, local: local, into: &localNearest)
        }
        let scale = DynamicCollisionMath.maximumScale(of: shape.transform)
        for index in localNearest.indices {
            guard let hit = localNearest[index]?.penetration else { continue }
            let direction = shape.transform * SIMD4<Float>(hit.normal, 0)
            let world = SIMD3(direction.x, direction.y, direction.z)
            guard simd_length_squared(world) > Float.ulpOfOne else { continue }
            let converted = DynamicPenetration(
                normal: simd_normalize(world), depth: hit.depth * scale
            )
            if converted.depth > (deepest[index]?.depth ?? -.greatestFiniteMagnitude) {
                deepest[index] = converted
            }
        }
    }

    /// Every sample against one surviving triangle, keeping each sample's
    /// nearest surface — whether or not that surface reported a penetration, so
    /// a near face saying "outside" still vetoes a far one. The sample's
    /// incumbent distance goes in, which lets the triangle dismiss itself on a
    /// dot product rather than a closest-point query.
    private static func accumulate(
        surface: DynamicSurfaceTriangle,
        local: DynamicLocalSamples,
        into nearest: inout [(distance: Float, penetration: DynamicPenetration?)?]
    ) {
        for index in local.points.indices {
            guard
                let hit = surface.surface(
                    of: local.points[index],
                    radius: local.radii[index],
                    recovery: local.recovery,
                    nearerThan: nearest[index]?.distance ?? .greatestFiniteMagnitude
                )
            else { continue }
            nearest[index] = hit
        }
    }

    /// Contacts between two dynamic bodies, taken in both directions so that
    /// neither shape's vertices are the only ones consulted. Friction and
    /// restitution are the geometric and the larger mean respectively, the
    /// usual pairing rules.
    public static func pairContacts(
        first: DynamicBodySamples,
        second: DynamicBodySamples
    ) -> [DynamicContact] {
        let material = DynamicContactMaterial(
            friction: (first.body.definition.friction * second.body.definition.friction)
                .squareRoot(),
            restitution: max(
                first.body.definition.restitution, second.body.definition.restitution
            )
        )
        return directional(sampling: first, against: second, material: material)
            + directional(sampling: second, against: first, material: material)
    }

    private static func directional(
        sampling: DynamicBodySamples,
        against obstacle: DynamicBodySamples,
        material: DynamicContactMaterial
    ) -> [DynamicContact] {
        sampling.samples.compactMap { sample in
            let radius = sample.radius + contactMargin
            guard let hit = obstacle.body.penetration(of: sample.point, radius: radius) else {
                return nil
            }
            return DynamicContact(
                body: sampling.index,
                other: obstacle.index,
                point: sample.point - hit.normal * (radius - hit.depth),
                normal: hit.normal,
                depth: hit.depth,
                friction: material.friction,
                restitution: material.restitution
            )
        }
    }
}
