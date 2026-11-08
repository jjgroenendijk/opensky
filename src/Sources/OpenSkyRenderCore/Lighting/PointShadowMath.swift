// Cube shadows of the shadow-casting point lights: which lights get one, and the six
// face views. The scene shader repeats the face rule. See docs/rendering/shadows.md.

import Foundation
public import simd

nonisolated public enum PointShadowMath {
    /// The game draws only a few shadow lights at once; 4 is OpenSky's value.
    public static let lightLimit = 4
    public static let faceCount = 6
    /// One cube face edge in texels.
    public static let resolution = 512
    /// World units; a caster closer to the light than this casts nothing.
    public static let nearPlane: Float = 8
    /// The receiver moves this far along its normal before the test, against acne.
    public static let receiverOffset: Float = 2

    /// +X, -X, +Y, -Y with Z up, then +Z, -Z with Y up.
    static let faces: [(forward: SIMD3<Float>, up: SIMD3<Float>)] = [
        (SIMD3(1, 0, 0), SIMD3(0, 0, 1)), (SIMD3(-1, 0, 0), SIMD3(0, 0, 1)),
        (SIMD3(0, 1, 0), SIMD3(0, 0, 1)), (SIMD3(0, -1, 0), SIMD3(0, 0, 1)),
        (SIMD3(0, 0, 1), SIMD3(0, 1, 0)), (SIMD3(0, 0, -1), SIMD3(0, 1, 0))
    ]

    /// The face whose axis is the largest component of `offset`, from the light.
    public static func face(of offset: SIMD3<Float>) -> Int {
        let axis = abs(offset)
        if axis.x >= axis.y, axis.x >= axis.z {
            return offset.x > 0 ? 0 : 1
        }
        if axis.y >= axis.z {
            return offset.y > 0 ? 2 : 3
        }
        return offset.z > 0 ? 4 : 5
    }

    /// World to clip for one 90-degree face; depth runs 0 at the near plane to 1 at the far one.
    public static func viewProjection(light: SIMD3<Float>, face: Int, radius: Float) -> float4x4 {
        let (forward, up) = faces[min(max(face, 0), faceCount - 1)]
        let right = simd_cross(forward, up)
        let view = float4x4(rows: [
            SIMD4(right, -simd_dot(right, light)),
            SIMD4(up, -simd_dot(up, light)),
            SIMD4(-forward, simd_dot(forward, light)),
            SIMD4(0, 0, 0, 1)
        ])
        let near = nearPlane
        let far = farPlane(radius: radius)
        let projection = float4x4(rows: [
            SIMD4(1, 0, 0, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, far / (near - far), near * far / (near - far)),
            SIMD4(0, 0, -1, 0)
        ])
        return projection * view
    }

    /// The far plane a light of `radius` draws to; the shader reads the same value.
    public static func farPlane(radius: Float) -> Float {
        radius.isFinite ? max(radius, nearPlane * 2) : nearPlane * 2
    }

    /// Up to `limit` light indices, nearest to the viewer first. A light whose sphere
    /// holds the viewer counts as distance 0; one past `reach` beyond its sphere is skipped.
    public static func pick(
        _ lights: [PointShadowCandidate],
        viewer: SIMD3<Float>,
        limit: Int = lightLimit,
        reach: Float = 4096
    ) -> [Int] {
        let gaps: [(index: Int, gap: Float)] = lights.map { light in
            let gap: Float = simd_distance(light.position, viewer) - light.radius
            return (index: light.index, gap: max(0, gap))
        }
        let reached = gaps.filter { $0.gap <= reach }
        let ordered = reached.sorted { lhs, rhs in
            lhs.gap == rhs.gap ? lhs.index < rhs.index : lhs.gap < rhs.gap
        }
        return ordered.prefix(max(limit, 0)).map(\.index)
    }
}

/// A shadow-casting point light: its index in the scene's list and its sphere.
nonisolated public struct PointShadowCandidate: Equatable, Sendable {
    public let index: Int
    public let position: SIMD3<Float>
    public let radius: Float

    public init(index: Int, position: SIMD3<Float>, radius: Float) {
        self.index = index
        self.position = position
        self.radius = radius
    }
}
