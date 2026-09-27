// Narrowphase for dynamic rigid bodies (issue #193, roadmap item 15.2): the
// contacts one body has with the immutable static world, and the contacts two
// dynamic bodies have with each other.
//
// Every contact is generated from a *sample point plus a skin radius* on one
// body tested against the other surface. That is the whole method, and it is
// what keeps the solver's inputs closed-form: a convex body's samples are its
// hull vertices or its capsule ends, and the question asked of the other
// surface is only ever "how deep is this sphere inside you".
//
// Against a triangle the answer has to be signed, because an unsigned distance
// flips the push direction the moment a corner passes through a floor. The sign
// comes from the triangle's own plane, oriented toward the body's centre of
// mass: a body is convex and its centre is always on the outside of a surface
// it is resting on, so that orientation is stable while a distance-only test is
// not. `recoveryDepth` bounds how far behind a surface a contact is still
// believed, so a body standing above a floor in one room is not dragged by a
// triangle in the room below.
//
// Documented in docs/engine/dynamic-bodies.md.

import simd

/// Placed triangle geometry a penetration query runs against, bundled so the
/// query stays inside the strict parameter cap.
nonisolated struct PlacedTriangleSoup {
    let vertices: [SIMD3<Float>]
    let indices: [UInt32]
    let transform: float4x4
}

/// One body's contact samples moved into a placed shape's own local space,
/// together with the box that bounds every one of them at its full reach.
///
/// The box is what makes the triangle pass affordable. A body carries a couple
/// of dozen samples and a candidate shape a few dozen triangles, so the pass is
/// a product of the two unless something cuts it: testing each triangle against
/// the *whole sample set* first turns twenty-odd rejects into one, and only the
/// few triangles that survive are prepared at all. `recovery` is what sizes the
/// box, which is why it is capped to the body rather than left at a flat
/// `recoveryDepth` — see `DynamicBodyContacts.recoveryDepth(of:)`.
nonisolated struct DynamicLocalSamples {
    let points: [SIMD3<Float>]
    /// Each sample's skin, with `contactMargin` added and the shape's scale
    /// divided out, so every length below is in the shape's own units.
    let radii: [Float]
    /// How this shape's triangles are turned into surface normals, in the same
    /// local space the samples are in.
    let orientation: DynamicSurfaceOrientation
    /// `recoveryDepth` in the shape's units.
    let recovery: Float
    /// Sample AABB grown by the largest sample reach.
    let lower: SIMD3<Float>
    let upper: SIMD3<Float>

    /// Nil where the shape's placement will not invert or a sample does not
    /// survive the transform, which leaves the shape contributing no contact
    /// rather than a nonsense one.
    init?(
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
nonisolated struct DynamicBodySamples {
    let body: DynamicBody
    /// The body's index in the solver's array.
    let index: Int
    let samples: [(point: SIMD3<Float>, radius: Float)]
}

/// The friction and restitution a pair of bodies contributes to its contacts.
nonisolated struct DynamicContactMaterial {
    let friction: Float
    let restitution: Float
}

/// One resolved touch. `normal` always points away from the obstacle and toward
/// `body`, so a positive normal impulse separates them.
nonisolated struct DynamicContact: Sendable {
    /// Index into the solver's body array.
    let body: Int
    /// The other dynamic body, or nil for a contact against static geometry.
    let other: Int?
    /// World-space contact point.
    let point: SIMD3<Float>
    let normal: SIMD3<Float>
    /// Positive overlap along `normal`.
    let depth: Float
    let friction: Float
    let restitution: Float
}

nonisolated enum DynamicBodyContacts {
    /// Collision margin every contact sample carries on top of its volume's own
    /// skin. A hull vertex has no skin of its own, so without a margin a resting
    /// box would generate contacts only while already interpenetrating and would
    /// jitter between touching and free. Engine units.
    static let contactMargin: Float = 1.5

    /// How far behind a surface a contact is still believed, in engine units.
    /// Past it the sample is taken to belong to different geometry rather than
    /// to a deep penetration of this one.
    static let recoveryDepth: Float = 48

    /// The same bound for one body, which is the smaller of `recoveryDepth` and
    /// the body's own reach.
    ///
    /// A sample cannot be meaningfully further inside a surface than the body it
    /// belongs to is big — past that the whole body would be buried, which is
    /// not a state vanilla authoring produces. Scaling the bound down for small
    /// clutter is also the single largest saving in the step: the bound inflates
    /// the box every triangle of a candidate shape is tested against, and a flat
    /// 48 units around a tankard let nearly half of a room's triangles through
    /// to the exact query.
    static func recoveryDepth(of body: DynamicBody) -> Float {
        min(recoveryDepth, max(contactMargin * 4, body.definition.boundingRadius))
    }

    /// Contacts between `body` and the placed static shapes `shapes`.
    ///
    /// Shapes are visited in the order the broadphase returned them, which is
    /// source-shape order and therefore stable, so the contact list is
    /// deterministic for a given pose.
    static func staticContacts(
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

    /// The deepest penetration of each sample into one placed shape, in sample
    /// order so the contact list stays deterministic.
    ///
    /// The triangle work runs in the *shape's* local space rather than in the
    /// world. A placed shape carries far more vertices than a body carries
    /// samples, so pushing a handful of samples through one inverse matrix beats
    /// pushing every triangle through the forward one — measured as the single
    /// largest cost in a step over a real interior. The shape's placement is
    /// rigid times a uniform scale (a REFR's XSCL, a body's and a shape's own
    /// rigid transforms), so a length in local space is a world length divided
    /// by that scale, and the answer converts back exactly.
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
    static func pairContacts(
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
