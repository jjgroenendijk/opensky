// Exact finite raycast over streamed NIF collision geometry (M8.4.1).
// Broadphase is the existing per-cell BVH; narrowphase transforms the ray
// into each shape's local space so affine placement keeps the world-ray
// distance parameter intact.

import simd

nonisolated private struct LocalInteractionRay {
    let origin: SIMD3<Float>
    let direction: SIMD3<Float>
    let maximumDistance: Float
}

nonisolated private struct InteractionTriangle {
    let first: SIMD3<Float>
    let second: SIMD3<Float>
    let third: SIMD3<Float>
}

nonisolated enum InteractionRaycaster {
    private static let epsilon: Float = 1e-5

    static func nearestHit(
        ray: InteractionRay,
        shapes: [StaticCollisionShape]
    ) -> InteractionRayHit? {
        var result: InteractionRayHit?
        for shape in shapes {
            guard let distance = hitDistance(ray: ray, shape: shape) else { continue }
            let candidate = InteractionRayHit(
                reference: shape.reference,
                position: ray.origin + ray.direction * distance,
                distance: distance
            )
            if shouldReplace(result, with: candidate) {
                result = candidate
            }
        }
        return result
    }

    private static func shouldReplace(
        _ current: InteractionRayHit?,
        with candidate: InteractionRayHit
    ) -> Bool {
        guard let current else { return true }
        if abs(candidate.distance - current.distance) <= epsilon {
            return candidate.reference.rawValue < current.reference.rawValue
        }
        return candidate.distance < current.distance
    }

    private static func hitDistance(
        ray: InteractionRay,
        shape: StaticCollisionShape
    ) -> Float? {
        let determinant = simd_determinant(shape.transform)
        guard determinant.isFinite, abs(determinant) > epsilon else { return nil }
        let inverse = shape.transform.inverse
        let localOrigin4 = inverse * SIMD4(ray.origin, 1)
        let localDirection4 = inverse * SIMD4(ray.direction, 0)
        let origin = SIMD3(localOrigin4.x, localOrigin4.y, localOrigin4.z)
        let direction = SIMD3(
            localDirection4.x, localDirection4.y, localDirection4.z
        )
        guard origin.isFinite, direction.isFinite else { return nil }
        let localRay = LocalInteractionRay(
            origin: origin,
            direction: direction,
            maximumDistance: ray.maximumDistance
        )

        let distance: Float? = switch shape.geometry {
        case let .triangleSoup(vertices, indices),
             let .convexVertices(vertices, indices):
            triangleDistance(
                origin: origin,
                direction: direction,
                vertices: vertices,
                indices: indices,
                maximumDistance: ray.maximumDistance
            )
        case let .box(halfExtents):
            boxDistance(
                origin: origin,
                direction: direction,
                halfExtents: halfExtents,
                maximumDistance: ray.maximumDistance
            )
        case let .sphere(radius):
            sphereDistance(
                origin: origin,
                direction: direction,
                center: .zero,
                radius: radius,
                maximumDistance: ray.maximumDistance
            )
        case let .capsule(first, second, radius):
            capsuleDistance(
                ray: localRay,
                first: first,
                second: second,
                radius: radius
            )
        }
        return distance.flatMap {
            $0 > epsilon && $0 <= ray.maximumDistance ? $0 : nil
        }
    }

    private static func triangleDistance(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        vertices: [SIMD3<Float>],
        indices: [UInt32],
        maximumDistance: Float
    ) -> Float? {
        var closest: Float?
        let end = indices.count - indices.count % 3
        for offset in stride(from: 0, to: end, by: 3) {
            let first = Int(indices[offset])
            let second = Int(indices[offset + 1])
            let third = Int(indices[offset + 2])
            guard first < vertices.count, second < vertices.count, third < vertices.count else {
                continue
            }
            guard
                let distance = triangleDistance(
                    origin: origin,
                    direction: direction,
                    triangle: InteractionTriangle(
                        first: vertices[first],
                        second: vertices[second],
                        third: vertices[third]
                    )
                ), distance <= maximumDistance
            else { continue }
            closest = min(closest ?? distance, distance)
        }
        return closest
    }

    private static func triangleDistance(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        triangle: InteractionTriangle
    ) -> Float? {
        let edge1 = triangle.second - triangle.first
        let edge2 = triangle.third - triangle.first
        let cross = simd_cross(direction, edge2)
        let determinant = simd_dot(edge1, cross)
        guard abs(determinant) > epsilon else { return nil }
        let inverse = 1 / determinant
        let relative = origin - triangle.first
        let firstWeight = inverse * simd_dot(relative, cross)
        guard firstWeight >= 0, firstWeight <= 1 else { return nil }
        let relativeCross = simd_cross(relative, edge1)
        let secondWeight = inverse * simd_dot(direction, relativeCross)
        guard secondWeight >= 0, firstWeight + secondWeight <= 1 else { return nil }
        let distance = inverse * simd_dot(edge2, relativeCross)
        return distance > epsilon ? distance : nil
    }

    private static func boxDistance(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        halfExtents: SIMD3<Float>,
        maximumDistance: Float
    ) -> Float? {
        var near: Float = 0
        var far = maximumDistance
        for axis in 0 ..< 3 {
            if abs(direction[axis]) <= epsilon {
                guard
                    origin[axis] >= -halfExtents[axis],
                    origin[axis] <= halfExtents[axis]
                else { return nil }
                continue
            }
            let inverse = 1 / direction[axis]
            var first = (-halfExtents[axis] - origin[axis]) * inverse
            var second = (halfExtents[axis] - origin[axis]) * inverse
            if first > second {
                swap(&first, &second)
            }
            near = max(near, first)
            far = min(far, second)
            guard near <= far else { return nil }
        }
        return near > epsilon ? near : (far > epsilon ? far : nil)
    }

    private static func sphereDistance(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        center: SIMD3<Float>,
        radius: Float,
        maximumDistance: Float
    ) -> Float? {
        guard radius > 0 else { return nil }
        let offset = origin - center
        let quadratic = simd_dot(direction, direction)
        let linear = simd_dot(offset, direction)
        let constant = simd_dot(offset, offset) - radius * radius
        let discriminant = linear * linear - quadratic * constant
        guard quadratic > epsilon, discriminant >= 0 else { return nil }
        let root = sqrt(discriminant)
        let first = (-linear - root) / quadratic
        let second = (-linear + root) / quadratic
        if first > epsilon, first <= maximumDistance {
            return first
        }
        return second > epsilon && second <= maximumDistance ? second : nil
    }

    private static func capsuleDistance(
        ray: LocalInteractionRay,
        first: SIMD3<Float>,
        second: SIMD3<Float>,
        radius: Float
    ) -> Float? {
        let axis = second - first
        let axisLengthSquared = simd_dot(axis, axis)
        guard axisLengthSquared > epsilon else {
            return sphereDistance(
                origin: ray.origin,
                direction: ray.direction,
                center: first,
                radius: radius,
                maximumDistance: ray.maximumDistance
            )
        }
        let offset = ray.origin - first
        let directionSquared = simd_dot(ray.direction, ray.direction)
        let axisDirection = simd_dot(axis, ray.direction)
        let axisOffset = simd_dot(axis, offset)
        let directionOffset = simd_dot(ray.direction, offset)
        let coefficient = axisLengthSquared * directionSquared
            - axisDirection * axisDirection
        let linear = axisLengthSquared * directionOffset - axisOffset * axisDirection
        let constant = axisLengthSquared * simd_dot(offset, offset)
            - axisOffset * axisOffset - radius * radius * axisLengthSquared

        var candidates: [Float] = []
        if
            let distance = sphereDistance(
                origin: ray.origin, direction: ray.direction, center: first,
                radius: radius, maximumDistance: ray.maximumDistance
            ), axisOffset + distance * axisDirection <= 0
        {
            candidates.append(distance)
        }
        if
            let distance = sphereDistance(
                origin: ray.origin, direction: ray.direction, center: second,
                radius: radius, maximumDistance: ray.maximumDistance
            ), axisOffset + distance * axisDirection >= axisLengthSquared
        {
            candidates.append(distance)
        }
        let discriminant = linear * linear - coefficient * constant
        if coefficient > epsilon, discriminant >= 0 {
            let root = sqrt(discriminant)
            for distance in [
                (-linear - root) / coefficient,
                (-linear + root) / coefficient
            ] {
                let height = axisOffset + distance * axisDirection
                if
                    distance > epsilon, distance <= ray.maximumDistance,
                    height >= 0, height <= axisLengthSquared
                {
                    candidates.append(distance)
                }
            }
        }
        return candidates.min()
    }
}

nonisolated extension SIMD3 where Scalar == Float {
    fileprivate var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}
