// Column-major, right-handed matrix helpers for the render pipeline.
// Conventions match Metal clip space: z in [0, 1], camera looks down -z.
// World space is Skyrim's Z-up right-handed basis at native units; see
// docs/decisions/coordinates.md for the binding conventions.

import simd

nonisolated enum MatrixMath {
    /// Basis change from Skyrim Z-up world axes to Metal-style y-up:
    /// (x, y, z) -> (x, z, -y). Proper rotation (det +1), no reflection.
    static let zUpToYUp = float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 0, -1, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))

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

    /// Counter-clockwise rotation about +X (viewed from the positive axis end).
    static func rotationX(radians: Float) -> float4x4 {
        let ct = cosf(radians)
        let st = sinf(radians)
        return float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, ct, st, 0),
            SIMD4<Float>(0, -st, ct, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    /// Counter-clockwise rotation about +Y.
    static func rotationY(radians: Float) -> float4x4 {
        let ct = cosf(radians)
        let st = sinf(radians)
        return float4x4(columns: (
            SIMD4<Float>(ct, 0, -st, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(st, 0, ct, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    /// Counter-clockwise rotation about +Z.
    static func rotationZ(radians: Float) -> float4x4 {
        let ct = cosf(radians)
        let st = sinf(radians)
        return float4x4(columns: (
            SIMD4<Float>(ct, st, 0, 0),
            SIMD4<Float>(-st, ct, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func translation(_ offset: SIMD3<Float>) -> float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(offset.x, offset.y, offset.z, 1)
        return matrix
    }

    static func scale(uniform factor: Float) -> float4x4 {
        float4x4(diagonal: SIMD4<Float>(factor, factor, factor, 1))
    }

    /// Right-handed view matrix: eye space has +x right, +y up, camera looking
    /// down -z. Works directly with Z-up world vectors — pass `up` = +Z and the
    /// Z-up -> y-up basis change falls out of the orthonormal construction.
    /// `up` must not be parallel to the view direction.
    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, up))
        let trueUp = simd_cross(right, forward)
        return float4x4(columns: (
            SIMD4<Float>(right.x, trueUp.x, -forward.x, 0),
            SIMD4<Float>(right.y, trueUp.y, -forward.y, 0),
            SIMD4<Float>(right.z, trueUp.z, -forward.z, 0),
            SIMD4<Float>(
                -simd_dot(right, eye),
                -simd_dot(trueUp, eye),
                simd_dot(forward, eye),
                1
            )
        ))
    }

    /// World transform of a placed reference (REFR): T * Rz(-z) * Ry(-y) * Rx(-x) * S.
    /// Bethesda euler angles turn clockwise viewed from the positive axis end,
    /// hence the negation against the CCW helpers above; order Z*Y*X with X
    /// innermost. Sign/order rationale + verification plan:
    /// docs/decisions/coordinates.md.
    static func placement(
        position: SIMD3<Float>,
        rotation: SIMD3<Float>,
        scale: Float
    ) -> float4x4 {
        translation(position)
            * rotationZ(radians: -rotation.z)
            * rotationY(radians: -rotation.y)
            * rotationX(radians: -rotation.x)
            * Self.scale(uniform: scale)
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
