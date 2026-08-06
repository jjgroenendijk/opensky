// Derived triangle connectivity for bhkConvexVerticesShape. NIF supplies a
// point cloud + half-space planes, not indexed faces; compute once per decoded
// model so every placed REFR shares it.

import Foundation
import simd

nonisolated enum NIFCollisionConvexHull {
    static func indices(vertices: [SIMD3<Float>], planes: [SIMD4<Float>]) -> [UInt32] {
        guard vertices.count >= 3, !planes.isEmpty else { return [] }
        let tolerance: Float = 0.02
        var result: [UInt32] = []
        var emittedFaces = Set<[Int]>()
        for plane in planes {
            let rawNormal = SIMD3(plane.x, plane.y, plane.z)
            let normalLength = simd_length(rawNormal)
            guard normalLength > Float.ulpOfOne else { continue }
            let normal = rawNormal / normalLength
            let signedDistance = plane.w / normalLength
            let face = vertices.indices.filter {
                abs(simd_dot(normal, vertices[$0]) + signedDistance) <= tolerance
            }
            guard face.count >= 3 else { continue }
            let faceKey = face.sorted()
            guard emittedFaces.insert(faceKey).inserted else { continue }
            appendFace(face, normal: normal, vertices: vertices, to: &result)
        }
        return result
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
