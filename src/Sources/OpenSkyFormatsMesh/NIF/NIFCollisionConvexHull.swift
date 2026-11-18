// Derived triangle connectivity for bhkConvexVerticesShape. NIF supplies a
// point cloud + half-space planes, not indexed faces; compute once per decoded
// model so every placed REFR shares it. See docs/formats/nif-collision.md.

import Foundation
import simd

nonisolated enum NIFCollisionConvexHull: Sendable {
    private static let tolerance: Float = 0.02

    /// One hull face: its outward normal, how far the hull reaches along it, and its points.
    private struct Face {
        let normal: SIMD3<Float>
        let extent: Float
        let points: [Int]
    }

    static func indices(vertices: [SIMD3<Float>], planes: [SIMD4<Float>]) -> [UInt32] {
        var result: [UInt32] = []
        for face in faces(vertices: vertices, planes: planes) {
            appendFace(face.points, normal: face.normal, vertices: vertices, to: &result)
        }
        return result
    }

    /// The hull grown by the convex radius: each face moves out along its normal by
    /// `radius`, and each point moves to where its faces meet again. Edges and corners
    /// stay sharp, where Havok rounds them.
    static func grown(
        vertices: [SIMD3<Float>], planes: [SIMD4<Float>], radius: Float
    ) -> (vertices: [SIMD3<Float>], indices: [UInt32]) {
        let faces = faces(vertices: vertices, planes: planes)
        guard radius > 0, radius.isFinite, !faces.isEmpty else {
            return (vertices, indices(vertices: vertices, planes: planes))
        }
        var touching = [[Int]](repeating: [], count: vertices.count)
        for (index, face) in faces.enumerated() {
            for point in face.points {
                touching[point].append(index)
            }
        }
        let moved = vertices.indices.map { point in
            grownPoint(vertices[point], faces: touching[point].map { faces[$0] }, radius: radius)
        }
        var result: [UInt32] = []
        for face in faces {
            appendFace(face.points, normal: face.normal, vertices: moved, to: &result)
        }
        return (moved, result)
    }

    /// A plane may sit outside the points by the shape's convex radius, so only its normal
    /// is used: the face is the points furthest along it.
    private static func faces(vertices: [SIMD3<Float>], planes: [SIMD4<Float>]) -> [Face] {
        guard vertices.count >= 3, !planes.isEmpty else { return [] }
        var result: [Face] = []
        var emittedFaces = Set<[Int]>()
        for plane in planes {
            let rawNormal = SIMD3(plane.x, plane.y, plane.z)
            let normalLength = simd_length(rawNormal)
            guard normalLength > Float.ulpOfOne else { continue }
            let normal = rawNormal / normalLength
            let extent = vertices.map { simd_dot(normal, $0) }.max() ?? 0
            let points = vertices.indices.filter {
                extent - simd_dot(normal, vertices[$0]) <= tolerance
            }
            guard points.count >= 3, emittedFaces.insert(points.sorted()).inserted else { continue }
            result.append(Face(normal: normal, extent: extent, points: points))
        }
        return result
    }

    /// The point nearest `point` that lies on each of its faces moved out by `radius`, by
    /// least squares. A small pull toward the pushed-out point keeps it defined when the
    /// faces do not fix all three axes.
    private static func grownPoint(
        _ point: SIMD3<Float>, faces: [Face], radius: Float
    ) -> SIMD3<Float> {
        guard !faces.isEmpty else { return point }
        let outward = faces.reduce(SIMD3<Float>.zero) { $0 + $1.normal }
        let length = simd_length(outward)
        let guess = SIMD3<Double>(length > .ulpOfOne ? point + outward / length * radius : point)
        let pull = 1e-6
        var normalMatrix = simd_double3x3(diagonal: SIMD3(repeating: pull))
        var target = guess * pull
        for face in faces {
            let normal = SIMD3<Double>(face.normal)
            normalMatrix += simd_double3x3(rows: [
                normal * normal.x,
                normal * normal.y,
                normal * normal.z
            ])
            target += normal * Double(face.extent + radius)
        }
        let solved = normalMatrix.inverse * target
        return solved.x.isFinite && solved.y.isFinite && solved.z.isFinite
            ? SIMD3<Float>(solved) : SIMD3<Float>(guess)
    }

    private static func appendFace(
        _ face: [Int],
        normal: SIMD3<Float>,
        vertices: [SIMD3<Float>],
        to result: inout [UInt32]
    ) {
        let center = face.reduce(SIMD3<Float>.zero) { $0 + vertices[$1] } / Float(face.count)
        let reference = abs(normal.z) < 0.9
            ? SIMD3<Float>(0, 0, 1)
            : SIMD3<Float>(1, 0, 0)
        let firstAxis = simd_normalize(simd_cross(reference, normal))
        let secondAxis = simd_cross(normal, firstAxis)
        let ordered = face.sorted { first, second in
            let firstOffset = vertices[first] - center
            let secondOffset = vertices[second] - center
            let firstAngle = atan2f(
                simd_dot(firstOffset, secondAxis),
                simd_dot(firstOffset, firstAxis)
            )
            let secondAngle = atan2f(
                simd_dot(secondOffset, secondAxis),
                simd_dot(secondOffset, firstAxis)
            )
            return firstAngle < secondAngle
        }
        guard let anchor = ordered.first else { return }
        for offset in 1 ..< ordered.count - 1 {
            let second = ordered[offset]
            let third = ordered[offset + 1]
            let winding = simd_dot(
                simd_cross(vertices[second] - vertices[anchor], vertices[third] - vertices[anchor]),
                normal
            )
            if winding >= 0 {
                result.append(contentsOf: [UInt32(anchor), UInt32(second), UInt32(third)])
            } else {
                result.append(contentsOf: [UInt32(anchor), UInt32(third), UInt32(second)])
            }
        }
    }
}
