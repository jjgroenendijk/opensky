// Where the sun sits on the screen, for the lens flare (docs/rendering/post-effects.md).

import simd

nonisolated public enum LensFlareMath {
    /// The sun's texture coordinate (0 to 1, y down), or nil when it is behind the camera
    /// or below the horizon. `toSun` points from the camera toward the sun.
    public static func sunScreenPosition(
        viewProjection: float4x4,
        camera: SIMD3<Float>,
        toSun: SIMD3<Float>
    ) -> SIMD2<Float>? {
        let length = simd_length(toSun)
        guard length > 0, toSun.z / length > 0 else { return nil }
        let point = camera + toSun / length * 100_000
        let clip = viewProjection * SIMD4(point, 1)
        guard clip.w > 0 else { return nil }
        let ndc = SIMD2(clip.x, clip.y) / clip.w
        return SIMD2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5)
    }
}
