// Contacts between one dynamic body and the placed static shapes near it. A
// compressed mesh is split into several placed shapes, so the nearest surface is
// chosen across all of them. See docs/engine/dynamic-narrowphase.md.

import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import simd

/// One sample's answer from one shape, in world units.
nonisolated struct DynamicSampleAnswer {
    var hit: DynamicPenetration?
    /// Distance to the triangle that gave `hit`.
    var hitDistance: Float = .greatestFiniteMagnitude
    /// Distance to the nearest triangle the sample is outside of.
    var outsideDistance: Float = .greatestFiniteMagnitude
}

nonisolated extension DynamicBodyContacts {
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
        let recovery = recoveryDepth(of: body)
        // A body's samples are its hull corners, so the same shape is asked
        // about eight times over. Testing them together builds each placed
        // triangle once per shape rather than once per sample.
        let answers = shapes.map { answers(of: samples, shape: $0, recovery: recovery) }
        var outside = [Float](repeating: .greatestFiniteMagnitude, count: samples.count)
        for shapeAnswers in answers {
            for sample in samples.indices {
                outside[sample] = min(outside[sample], shapeAnswers[sample].outsideDistance)
            }
        }
        var result: [DynamicContact] = []
        for (shape, shapeAnswers) in zip(shapes, answers) {
            for (sampleIndex, answer) in shapeAnswers.enumerated() {
                guard let hit = answer.hit else { continue }
                let sample = samples[sampleIndex]
                let radius = sample.radius + contactMargin
                // Behind a face, a nearer face of another shape that the sample is
                // outside of wins, as it does inside one shape: a jug standing on a
                // board is not inside the board's underside.
                if hit.depth > radius, answer.hitDistance > outside[sampleIndex] {
                    continue
                }
                result.append(DynamicContact(
                    body: index,
                    other: nil,
                    point: sample.point - hit.normal * (radius - hit.depth),
                    normal: hit.normal,
                    depth: hit.depth,
                    friction: body.definition.friction,
                    restitution: body.definition.restitution,
                    surfaceMaterial: shape.material
                ))
            }
        }
        return result
    }

    /// Each sample's deepest penetration into one placed shape and its nearest
    /// outside face, in sample order. The work runs in the shape's local space:
    /// moving a few samples through one inverse matrix is cheaper than moving
    /// every triangle. The placement is rigid times uniform scale, so lengths
    /// convert back exactly.
    private static func answers(
        of samples: [(point: SIMD3<Float>, radius: Float)],
        shape: StaticCollisionShape,
        recovery: Float
    ) -> [DynamicSampleAnswer] {
        var answers = [DynamicSampleAnswer](repeating: DynamicSampleAnswer(), count: samples.count)
        let soup: (vertices: [SIMD3<Float>], indices: [UInt32])
        switch shape.geometry {
        case let .triangleSoup(vertices, indices),
             let .convexVertices(vertices, indices):
            soup = (vertices, indices)
        case let .box(halfExtents):
            soup = (CapsuleWorldCollider.boxVertices(halfExtents), CapsuleWorldCollider.boxIndices)
        case .sphere, .capsule:
            for (index, sample) in samples.enumerated() {
                answers[index].hit = penetration(
                    of: sample.point, radius: sample.radius + contactMargin, shape: shape
                )
            }
            return answers
        }
        guard
            let local = DynamicLocalSamples(samples: samples, shape: shape, recovery: recovery)
        else { return answers }
        accumulate(soup: soup, against: local, shape: shape, into: &answers)
        return answers
    }

    /// One pass over a shape's own triangles, keeping every sample's nearest
    /// surface. The samples arrive already in the shape's space; the answers are
    /// moved back to the world before they are returned.
    private static func accumulate(
        soup: (vertices: [SIMD3<Float>], indices: [UInt32]),
        against local: DynamicLocalSamples,
        shape: StaticCollisionShape,
        into answers: inout [DynamicSampleAnswer]
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
            // clutter.
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
            guard let nearest = localNearest[index] else { continue }
            guard let hit = nearest.penetration else {
                answers[index].outsideDistance = nearest.distance * scale
                continue
            }
            let direction = shape.transform * SIMD4<Float>(hit.normal, 0)
            let world = SIMD3(direction.x, direction.y, direction.z)
            guard simd_length_squared(world) > Float.ulpOfOne else { continue }
            answers[index].hit = DynamicPenetration(
                normal: simd_normalize(world), depth: hit.depth * scale
            )
            answers[index].hitDistance = nearest.distance * scale
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
}
