// World-to-listener conversion for 3D audio. Skyrim is right-handed Z-up in units of
// 0.0142875 m; the listener space is right-handed Y-up in meters. So positions map
// (x, y, z) -> (x, z, -y), as `MatrixMath.zUpToYUp` does, then scale to meters;
// directions are not scaled. See docs/engine/audio.md.

import simd

nonisolated public enum AudioSpace: Sendable {
    /// Creation Kit unit scale: 1 unit = 0.0142875 m (docs/decisions/coordinates.md).
    public static let metersPerUnit: Float = 0.0142875

    /// World position (native units, Z-up) to listener-space position (meters, Y-up).
    public static func listenerPosition(fromWorld position: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(position.x, position.z, -position.y) * metersPerUnit
    }

    /// World direction (Z-up) to listener-space direction (Y-up). No unit scale:
    /// directions carry orientation, not distance.
    public static func listenerDirection(fromWorld direction: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(direction.x, direction.z, -direction.y)
    }

    /// Camera forward vector in world space from the free-fly pose convention:
    /// yaw rotates about world +Z (0 -> +X east, +pi/2 -> +Y north), pitch
    /// elevates the view (positive looks up). Matches `FreeFlyCamera`.
    public static func worldForward(yaw: Float, pitch: Float) -> SIMD3<Float> {
        SIMD3(
            cosf(yaw) * cosf(pitch),
            sinf(yaw) * cosf(pitch),
            sinf(pitch)
        )
    }

    /// Camera up vector in world space for the same pose: orthogonal to forward,
    /// in the vertical plane the camera tilts in. At zero pitch this is world +Z.
    public static func worldUp(yaw: Float, pitch: Float) -> SIMD3<Float> {
        SIMD3(
            -cosf(yaw) * sinf(pitch),
            -sinf(yaw) * sinf(pitch),
            cosf(pitch)
        )
    }

    /// Distance between two world positions, in meters — what the attenuation
    /// model sees for a source/listener pair.
    public static func distanceMeters(
        fromWorld first: SIMD3<Float>,
        toWorld second: SIMD3<Float>
    ) -> Float {
        simd_distance(first, second) * metersPerUnit
    }
}
