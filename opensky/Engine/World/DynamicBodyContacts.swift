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
                of: samples, shape: shape, center: body.previousPosition
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
        center: SIMD3<Float>
    ) -> [(sample: (point: SIMD3<Float>, radius: Float), hit: DynamicPenetration)] {
        var deepest = [DynamicPenetration?](repeating: nil, count: samples.count)
        switch shape.geometry {
        case let .triangleSoup(vertices, indices),
             let .convexVertices(vertices, indices):
            accumulate(
                soup: (vertices: vertices, indices: indices),
                against: samples,
                shape: shape,
                center: center,
                into: &deepest
            )
        case let .box(halfExtents):
            accumulate(
                soup: (
                    vertices: CapsuleWorldCollider.boxVertices(halfExtents),
                    indices: CapsuleWorldCollider.boxIndices
                ),
                against: samples,
                shape: shape,
                center: center,
                into: &deepest
            )
        case .sphere, .capsule:
            for (index, sample) in samples.enumerated() {
                deepest[index] = penetration(
                    of: sample.point,
                    radius: sample.radius + contactMargin,
                    shape: shape,
                    center: center
                )
            }
        }
        return samples.indices.compactMap { index in
            deepest[index].map { (sample: samples[index], hit: $0) }
        }
    }

    /// One pass over a shape's own triangles, deepening every sample's answer as
    /// it goes. Samples arrive in world space and are moved into the shape's
    /// space here; the answers are moved back before they are returned.
    private static func accumulate(
        soup: (vertices: [SIMD3<Float>], indices: [UInt32]),
        against samples: [(point: SIMD3<Float>, radius: Float)],
        shape: StaticCollisionShape,
        center: SIMD3<Float>,
        into deepest: inout [DynamicPenetration?]
    ) {
        let determinant = simd_determinant(shape.transform)
        let scale = DynamicCollisionMath.maximumScale(of: shape.transform)
        guard determinant.isFinite, abs(determinant) > 1e-9, scale > Float.ulpOfOne else {
            return
        }
        let inverse = shape.transform.inverse
        let localCenter = DynamicCollisionMath.transform(center, by: inverse)
        let local = samples.map {
            (
                point: DynamicCollisionMath.transform($0.point, by: inverse),
                radius: ($0.radius + contactMargin) / scale
            )
        }
        guard localCenter.isFiniteVector, local.allSatisfy(\.point.isFiniteVector) else {
            return
        }
        let vertices = soup.vertices
        let indices = soup.indices
        let end = indices.count - indices.count % 3
        var localNearest = [(penetration: DynamicPenetration, distance: Float)?](
            repeating: nil, count: samples.count
        )
        for offset in stride(from: 0, to: end, by: 3) {
            let first = Int(indices[offset])
            let second = Int(indices[offset + 1])
            let third = Int(indices[offset + 2])
            guard first < vertices.count, second < vertices.count, third < vertices.count else {
                continue
            }
            let triangle = CollisionTriangle(
                first: vertices[first], second: vertices[second], third: vertices[third]
            )
            for (index, sample) in local.enumerated() {
                guard
                    let hit = trianglePenetration(
                        of: sample.point,
                        radius: sample.radius,
                        triangle: triangle,
                        center: localCenter,
                        recovery: recoveryDepth / scale
                    ), hit.distance < (localNearest[index]?.distance ?? .greatestFiniteMagnitude)
                else { continue }
                localNearest[index] = hit
            }
        }
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
