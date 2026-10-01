// View-frustum vs world AABB culling. Planes per Gribb and Hartmann (2001), from the
// rows of view-projection because OpenSky uses column vectors
// (docs/decisions/coordinates.md). Metal clip z is [0, 1], so near is row2 alone and
// far is row3 - row2, checked against `MatrixMath.perspective`.

import OpenSkyFormatsCore
import simd

/// Six inward-facing view-frustum planes, extracted from a view-projection
/// matrix. Each plane satisfies `dot(normal, point) + d >= 0` for points on the
/// inside (visible) half-space; `normal` (plane.xyz) is unit length.
nonisolated public struct Frustum: Sendable {
    /// Left, right, bottom, top, near, far, in that order.
    public let planes: [SIMD4<Float>]

    /// `viewProjection` is the combined `P * V` matrix (column-vector
    /// convention: `clip = viewProjection * v`) — no model matrix, since this
    /// operates in world space against world-space AABBs.
    public init(viewProjection matrix: float4x4) {
        func row(_ i: Int) -> SIMD4<Float> {
            SIMD4(
                matrix.columns.0[i], matrix.columns.1[i],
                matrix.columns.2[i], matrix.columns.3[i]
            )
        }
        let r0 = row(0)
        let r1 = row(1)
        let r2 = row(2)
        let r3 = row(3)

        // Metal clip range z in [0, 1]: near is clip.z >= 0 (row2 alone), far is
        // clip.w - clip.z >= 0 (row3 - row2). x/y stay the usual +-1 NDC pairs.
        planes = [r3 + r0, r3 - r0, r3 + r1, r3 - r1, r2, r3 - r2].map(Self.normalized)
    }

    private static func normalized(_ plane: SIMD4<Float>) -> SIMD4<Float> {
        let length = simd_length(SIMD3(plane.x, plane.y, plane.z))
        // Degenerate (zero-length normal) input matrix — pathological, keep the
        // plane as-is rather than dividing by zero into NaNs.
        guard length > .ulpOfOne else { return plane }
        return plane / length
    }

    /// Conservative AABB-vs-frustum test using the positive-vertex (p-vertex)
    /// method: for each plane, test the box corner furthest along the plane's
    /// normal. The box is outside only if that single corner is outside — so a
    /// box straddling a plane, or fully inside all six, tests `true`. Never
    /// culls a box that is actually visible; may keep one that is not.
    public func intersects(min: SIMD3<Float>, max: SIMD3<Float>) -> Bool {
        for plane in planes {
            let normal = SIMD3(plane.x, plane.y, plane.z)
            let pVertex = SIMD3(
                normal.x >= 0 ? max.x : min.x,
                normal.y >= 0 ? max.y : min.y,
                normal.z >= 0 ? max.z : min.z
            )
            if simd_dot(normal, pVertex) + plane.w < 0 {
                return false
            }
        }
        return true
    }

    /// Convenience overload for `ModelBounds` (Rendering/MeshLibrary.swift) so
    /// callers with a model-space-derived world AABB don't have to unpack
    /// min/max by hand. The core test stays decoupled from `ModelBounds`.
    public func intersects(_ bounds: ModelBounds) -> Bool {
        intersects(min: bounds.min, max: bounds.max)
    }
}
