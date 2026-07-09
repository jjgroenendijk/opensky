// Column-major, right-handed matrix helpers for the render pipeline.
// Conventions match Metal clip space: z in [0, 1], camera looks down -z.

import simd

nonisolated enum MatrixMath {
    static func radians(fromDegrees degrees: Float) -> Float {
        degrees / 180 * .pi
    }

    /// Rodrigues rotation about an arbitrary axis.
    static func rotation(radians: Float, axis: SIMD3<Float>) -> float4x4 {
        let unit = simd_normalize(axis)
        let ct = cosf(radians)
        let st = sinf(radians)
        let ci = 1 - ct
        let x = unit.x
        let y = unit.y
        let z = unit.z
        return float4x4(columns: (
            SIMD4<Float>(ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
            SIMD4<Float>(x * y * ci - z * st, ct + y * y * ci, z * y * ci + x * st, 0),
            SIMD4<Float>(x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func translation(_ offset: SIMD3<Float>) -> float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(offset.x, offset.y, offset.z, 1)
        return matrix
    }

    /// Right-handed perspective projection mapping z to Metal's [0, 1] range.
    static func perspective(
        fovYRadians: Float,
        aspectRatio: Float,
        nearZ: Float,
        farZ: Float
    ) -> float4x4 {
        let ys = 1 / tanf(fovYRadians * 0.5)
        let xs = ys / aspectRatio
        let zs = farZ / (nearZ - farZ)
        return float4x4(columns: (
            SIMD4<Float>(xs, 0, 0, 0),
            SIMD4<Float>(0, ys, 0, 0),
            SIMD4<Float>(0, 0, zs, -1),
            SIMD4<Float>(0, 0, zs * nearZ, 0)
        ))
    }
}
