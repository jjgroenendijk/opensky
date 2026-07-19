// Upright player-capsule narrowphase + iterative collide-and-slide response.
// Shapes are engine-facing values from StaticCollisionWorld; no NIF disk
// layout leaks into movement.

import simd

nonisolated struct CapsuleCollisionContact {
    let normal: SIMD3<Float>
    let depth: Float
}

nonisolated struct CapsuleMoveResult {
    let position: SIMD3<Float>
    let contacts: [CapsuleCollisionContact]
    let hasUnresolvedPenetration: Bool
}

nonisolated private struct CollisionTriangle {
    let first: SIMD3<Float>
    let second: SIMD3<Float>
    let third: SIMD3<Float>
}

nonisolated private func capsuleResponseNormal(
    _ normal: SIMD3<Float>,
    motion: SIMD3<Float>
) -> SIMD3<Float> {
    let minimumUp = cosf(MatrixMath.radians(fromDegrees: WalkController.maximumSlopeDegrees))
    guard
        normal.z > 0,
        normal.z < minimumUp,
        simd_length_squared(SIMD2(motion.x, motion.y)) > Float.ulpOfOne
    else { return normal }
    let horizontal = SIMD3<Float>(normal.x, normal.y, 0)
    let length = simd_length(horizontal)
    return length > Float.ulpOfOne ? horizontal / length : normal
}

nonisolated struct CapsuleWorldCollider {
    typealias CandidateQuery = (ModelBounds) -> [StaticCollisionShape]

    private static let contactTolerance: Float = 0.02
    private static let separationSlop: Float = 0.002
    private static let maximumIterations = 8

    let capsule: PlayerCapsule

    func move(
        from start: SIMD3<Float>,
        displacement: SIMD3<Float>,
        query: CandidateQuery
    ) -> CapsuleMoveResult {
        let distance = simd_length(displacement)
        let maximumSubmove = max(capsule.radius * 0.5, 1)
        let submoveCount = max(1, Int(ceilf(distance / maximumSubmove)))
        let submove = displacement / Float(submoveCount)
        var position = start
        var unresolved = false
        for _ in 0 ..< submoveCount {
            let destination = position + submove
            let bounds = contactBounds(at: position).union(contactBounds(at: destination))
            let shapes = query(bounds)
            var candidate = destination
            unresolved = solvePenetrations(
                position: &candidate,
                motion: submove,
                shapes: shapes
            ) || unresolved
            position = candidate
        }
        let contacts = contacts(
            at: position,
            motion: displacement,
            shapes: query(contactBounds(at: position))
        ).filter { $0.depth >= -Self.contactTolerance }
        return CapsuleMoveResult(
            position: position,
            contacts: contacts,
            hasUnresolvedPenetration: unresolved
        )
    }

    private func contactBounds(at feet: SIMD3<Float>) -> ModelBounds {
        let bounds = capsuleBounds(at: feet)
        let tolerance = SIMD3<Float>(repeating: Self.contactTolerance)
        return ModelBounds(min: bounds.min - tolerance, max: bounds.max + tolerance)
    }

    private func solvePenetrations(
        position: inout SIMD3<Float>,
        motion: SIMD3<Float>,
        shapes: [StaticCollisionShape]
    ) -> Bool {
        for _ in 0 ..< Self.maximumIterations {
            let allContacts = contacts(at: position, motion: motion, shapes: shapes)
            let eligible = allContacts.filter { $0.depth > Self.separationSlop }
            guard let contact = eligible.max(by: { $0.depth < $1.depth }) else { return false }
            position += capsuleResponseNormal(contact.normal, motion: motion)
                * (contact.depth + Self.separationSlop)
        }
        return contacts(at: position, motion: motion, shapes: shapes)
            .contains { $0.depth > Self.contactTolerance }
    }

    private func contacts(
        at feet: SIMD3<Float>,
        motion: SIMD3<Float>,
        shapes: [StaticCollisionShape]
    ) -> [CapsuleCollisionContact] {
        let segment = capsuleSegment(at: feet)
        return shapes.flatMap { contacts(segment: segment, motion: motion, shape: $0) }
    }

    private func capsuleSegment(
        at feet: SIMD3<Float>
    ) -> (first: SIMD3<Float>, second: SIMD3<Float>) {
        (
            feet + SIMD3<Float>(0, 0, capsule.radius),
            feet + SIMD3<Float>(0, 0, capsule.height - capsule.radius)
        )
    }

    private func contacts(
        segment: (first: SIMD3<Float>, second: SIMD3<Float>),
        motion: SIMD3<Float>,
        shape: StaticCollisionShape
    ) -> [CapsuleCollisionContact] {
        switch shape.geometry {
        case let .triangleSoup(vertices, indices):
            return triangleContacts(
                segment: segment,
                motion: motion,
                vertices: vertices,
                indices: indices,
                transform: shape.transform
            )
        case let .convexVertices(vertices, hullIndices):
            return triangleContacts(
                segment: segment,
                motion: motion,
                vertices: vertices,
                indices: hullIndices,
                transform: shape.transform
            )
        case let .box(halfExtents):
            return triangleContacts(
                segment: segment,
                motion: motion,
                vertices: Self.boxVertices(halfExtents),
                indices: Self.boxIndices,
                transform: shape.transform
            )
        case let .sphere(radius):
            let center = Self.transform(.zero, by: shape.transform)
            let scaledRadius = radius * Self.maximumScale(of: shape.transform)
            return sphereContact(
                segment: segment,
                motion: motion,
                center: center,
                radius: scaledRadius
            ).map { [$0] } ?? []
        case let .capsule(first, second, radius):
            let obstacle = (
                Self.transform(first, by: shape.transform),
                Self.transform(second, by: shape.transform)
            )
            return capsuleContact(
                segment: segment,
                motion: motion,
                obstacle: obstacle,
                radius: radius * Self.maximumScale(of: shape.transform)
            ).map { [$0] } ?? []
        }
    }

    private func triangleContacts(
        segment: (first: SIMD3<Float>, second: SIMD3<Float>),
        motion: SIMD3<Float>,
        vertices: [SIMD3<Float>],
        indices: [UInt32],
        transform: float4x4
    ) -> [CapsuleCollisionContact] {
        var result: [CapsuleCollisionContact] = []
        for offset in stride(from: 0, to: indices.count - indices.count % 3, by: 3) {
            let first = Self.transform(vertices[Int(indices[offset])], by: transform)
            let second = Self.transform(vertices[Int(indices[offset + 1])], by: transform)
            let third = Self.transform(vertices[Int(indices[offset + 2])], by: transform)
            let triangle = CollisionTriangle(first: first, second: second, third: third)
            guard
                let contact = triangleContact(
                    segment: segment,
                    motion: motion,
                    triangle: triangle
                ) else { continue }
            result.append(contact)
        }
        return result
    }

    private func triangleContact(
        segment: (first: SIMD3<Float>, second: SIMD3<Float>),
        motion: SIMD3<Float>,
        triangle: CollisionTriangle
    ) -> CapsuleCollisionContact? {
        let closest = Self.closestSegmentTriangle(segment, triangle)
        let delta = closest.segment - closest.surface
        let distance = simd_length(delta)
        guard distance <= capsule.radius + Self.contactTolerance else { return nil }
        let normal: SIMD3<Float>
        if distance > Float.ulpOfOne {
            normal = delta / distance
        } else {
            let raw = simd_cross(
                triangle.second - triangle.first,
                triangle.third - triangle.first
            )
            guard simd_length_squared(raw) > Float.ulpOfOne else { return nil }
            var oriented = simd_normalize(raw)
            let midpoint = (segment.first + segment.second) * 0.5
            let side = simd_dot(oriented, midpoint - triangle.first)
            if side < 0 || (abs(side) <= Self.contactTolerance && simd_dot(oriented, motion) > 0) {
                oriented = -oriented
            }
            normal = oriented
        }
        return CapsuleCollisionContact(normal: normal, depth: capsule.radius - distance)
    }

    private func sphereContact(
        segment: (first: SIMD3<Float>, second: SIMD3<Float>),
        motion: SIMD3<Float>,
        center: SIMD3<Float>,
        radius: Float
    ) -> CapsuleCollisionContact? {
        let point = Self.closestPoint(on: segment, to: center)
        return radialContact(
            capsulePoint: point,
            obstaclePoint: center,
            combinedRadius: capsule.radius + radius,
            motion: motion
        )
    }

    private func capsuleContact(
        segment: (first: SIMD3<Float>, second: SIMD3<Float>),
        motion: SIMD3<Float>,
        obstacle: (SIMD3<Float>, SIMD3<Float>),
        radius: Float
    ) -> CapsuleCollisionContact? {
        let closest = Self.closestSegments(segment, obstacle)
        return radialContact(
            capsulePoint: closest.first,
            obstaclePoint: closest.second,
            combinedRadius: capsule.radius + radius,
            motion: motion
        )
    }

    private func radialContact(
        capsulePoint: SIMD3<Float>,
        obstaclePoint: SIMD3<Float>,
        combinedRadius: Float,
        motion: SIMD3<Float>
    ) -> CapsuleCollisionContact? {
        let delta = capsulePoint - obstaclePoint
        let distance = simd_length(delta)
        guard distance <= combinedRadius + Self.contactTolerance else { return nil }
        let normal: SIMD3<Float>
        if distance > Float.ulpOfOne {
            normal = delta / distance
        } else {
            let motionLength = simd_length(motion)
            normal = motionLength > Float.ulpOfOne ? -motion / motionLength : SIMD3(0, 0, 1)
        }
        return CapsuleCollisionContact(normal: normal, depth: combinedRadius - distance)
    }
}

nonisolated extension CapsuleWorldCollider {
    static let boxIndices: [UInt32] = [
        0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7,
        0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5,
        2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7
    ]

    static func boxVertices(_ half: SIMD3<Float>) -> [SIMD3<Float>] {
        [
            SIMD3(-half.x, -half.y, -half.z), SIMD3(half.x, -half.y, -half.z),
            SIMD3(half.x, half.y, -half.z), SIMD3(-half.x, half.y, -half.z),
            SIMD3(-half.x, -half.y, half.z), SIMD3(half.x, -half.y, half.z),
            SIMD3(half.x, half.y, half.z), SIMD3(-half.x, half.y, half.z)
        ]
    }

    fileprivate static func transform(_ point: SIMD3<Float>, by matrix: float4x4) -> SIMD3<Float> {
        let transformed = matrix * SIMD4<Float>(point, 1)
        return SIMD3(transformed.x, transformed.y, transformed.z)
    }

    fileprivate static func maximumScale(of matrix: float4x4) -> Float {
        max(
            simd_length(SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)),
            simd_length(SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)),
            simd_length(SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
        )
    }

    fileprivate static func closestSegmentTriangle(
        _ segment: (SIMD3<Float>, SIMD3<Float>),
        _ triangle: CollisionTriangle
    ) -> (segment: SIMD3<Float>, surface: SIMD3<Float>) {
        let direction = segment.1 - segment.0
        let normal = simd_cross(
            triangle.second - triangle.first,
            triangle.third - triangle.first
        )
        let denominator = simd_dot(normal, direction)
        if abs(denominator) > Float.ulpOfOne {
            let time = simd_dot(normal, triangle.first - segment.0) / denominator
            if time >= 0, time <= 1 {
                let point = segment.0 + direction * time
                if pointInTriangle(point, triangle) {
                    return (point, point)
                }
            }
        }

        var best = (segment.0, closestPoint(on: triangle, to: segment.0))
        var bestDistance = simd_distance_squared(best.0, best.1)
        let endpoint = closestPoint(on: triangle, to: segment.1)
        let endpointDistance = simd_distance_squared(segment.1, endpoint)
        if endpointDistance < bestDistance {
            best = (segment.1, endpoint)
            bestDistance = endpointDistance
        }
        let edges = [
            (triangle.first, triangle.second),
            (triangle.second, triangle.third),
            (triangle.third, triangle.first)
        ]
        for edge in edges {
            let pair = closestSegments(segment, edge)
            let distance = simd_distance_squared(pair.first, pair.second)
            if distance < bestDistance {
                best = pair
                bestDistance = distance
            }
        }
        return best
    }

    fileprivate static func pointInTriangle(
        _ point: SIMD3<Float>,
        _ triangle: CollisionTriangle
    ) -> Bool {
        let first = triangle.second - triangle.first
        let second = triangle.third - triangle.first
        let relative = point - triangle.first
        let firstFirst = simd_dot(first, first)
        let firstSecond = simd_dot(first, second)
        let secondSecond = simd_dot(second, second)
        let relativeFirst = simd_dot(relative, first)
        let relativeSecond = simd_dot(relative, second)
        let denominator = firstFirst * secondSecond - firstSecond * firstSecond
        guard abs(denominator) > Float.ulpOfOne else { return false }
        let u = (secondSecond * relativeFirst - firstSecond * relativeSecond) / denominator
        let v = (firstFirst * relativeSecond - firstSecond * relativeFirst) / denominator
        return u >= 0 && v >= 0 && u + v <= 1
    }

    fileprivate static func closestPoint(
        on triangle: CollisionTriangle,
        to point: SIMD3<Float>
    ) -> SIMD3<Float> {
        let vertexA = triangle.first
        let vertexB = triangle.second
        let vertexC = triangle.third
        let edgeAB = vertexB - vertexA
        let edgeAC = vertexC - vertexA
        let offsetA = point - vertexA
        let dotABOffsetA = simd_dot(edgeAB, offsetA)
        let dotACOffsetA = simd_dot(edgeAC, offsetA)
        if dotABOffsetA <= 0, dotACOffsetA <= 0 {
            return vertexA
        }
        let offsetB = point - vertexB
        let dotABOffsetB = simd_dot(edgeAB, offsetB)
        let dotACOffsetB = simd_dot(edgeAC, offsetB)
        if dotABOffsetB >= 0, dotACOffsetB <= dotABOffsetB {
            return vertexB
        }
        let vertexRegionC = dotABOffsetA * dotACOffsetB - dotABOffsetB * dotACOffsetA
        if vertexRegionC <= 0, dotABOffsetA >= 0, dotABOffsetB <= 0 {
            return vertexA + edgeAB * (dotABOffsetA / (dotABOffsetA - dotABOffsetB))
        }
        let offsetC = point - vertexC
        let dotABOffsetC = simd_dot(edgeAB, offsetC)
        let dotACOffsetC = simd_dot(edgeAC, offsetC)
        if dotACOffsetC >= 0, dotABOffsetC <= dotACOffsetC {
            return vertexC
        }
        let vertexRegionB = dotABOffsetC * dotACOffsetA - dotABOffsetA * dotACOffsetC
        if vertexRegionB <= 0, dotACOffsetA >= 0, dotACOffsetC <= 0 {
            return vertexA + edgeAC * (dotACOffsetA / (dotACOffsetA - dotACOffsetC))
        }
        let vertexRegionA = dotABOffsetB * dotACOffsetC - dotABOffsetC * dotACOffsetB
        let insideEdgeBC = vertexRegionA <= 0
            && dotACOffsetB - dotABOffsetB >= 0
            && dotABOffsetC - dotACOffsetC >= 0
        if insideEdgeBC {
            let edgeBC = vertexC - vertexB
            let weight = (dotACOffsetB - dotABOffsetB)
                / ((dotACOffsetB - dotABOffsetB) + (dotABOffsetC - dotACOffsetC))
            return vertexB + edgeBC * weight
        }
        let denominator = 1 / (vertexRegionA + vertexRegionB + vertexRegionC)
        return vertexA
            + edgeAB * (vertexRegionB * denominator)
            + edgeAC * (vertexRegionC * denominator)
    }

    fileprivate static func closestPoint(
        on segment: (SIMD3<Float>, SIMD3<Float>),
        to point: SIMD3<Float>
    ) -> SIMD3<Float> {
        let delta = segment.1 - segment.0
        let lengthSquared = simd_length_squared(delta)
        guard lengthSquared > Float.ulpOfOne else { return segment.0 }
        let time = max(0, min(1, simd_dot(point - segment.0, delta) / lengthSquared))
        return segment.0 + delta * time
    }

    fileprivate static func closestSegments(
        _ first: (SIMD3<Float>, SIMD3<Float>),
        _ second: (SIMD3<Float>, SIMD3<Float>)
    ) -> (first: SIMD3<Float>, second: SIMD3<Float>) {
        let d1 = first.1 - first.0
        let d2 = second.1 - second.0
        let offset = first.0 - second.0
        let firstLengthSquared = simd_dot(d1, d1)
        let secondLengthSquared = simd_dot(d2, d2)
        let secondOffsetDot = simd_dot(d2, offset)
        var firstTime: Float = 0
        var secondTime: Float = 0
        if firstLengthSquared <= Float.ulpOfOne {
            secondTime = secondLengthSquared > Float.ulpOfOne
                ? max(0, min(1, secondOffsetDot / secondLengthSquared)) : 0
        } else {
            let firstOffsetDot = simd_dot(d1, offset)
            if secondLengthSquared <= Float.ulpOfOne {
                firstTime = max(0, min(1, -firstOffsetDot / firstLengthSquared))
            } else {
                let directionsDot = simd_dot(d1, d2)
                let denominator = firstLengthSquared * secondLengthSquared
                    - directionsDot * directionsDot
                if abs(denominator) > Float.ulpOfOne {
                    firstTime = max(0, min(1, (
                        directionsDot * secondOffsetDot
                            - firstOffsetDot * secondLengthSquared
                    ) / denominator))
                }
                secondTime = (directionsDot * firstTime + secondOffsetDot)
                    / secondLengthSquared
                if secondTime < 0 {
                    secondTime = 0
                    firstTime = max(0, min(1, -firstOffsetDot / firstLengthSquared))
                } else if secondTime > 1 {
                    secondTime = 1
                    firstTime = max(0, min(1, (
                        directionsDot - firstOffsetDot
                    ) / firstLengthSquared))
                }
            }
        }
        return (first.0 + d1 * firstTime, second.0 + d2 * secondTime)
    }
}
