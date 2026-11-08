// Which side of a ward holder a spell must come from to be blocked.

import simd

nonisolated public enum WardArc {
    /// Half of the ward's front arc. UESP "Skyrim:Ward": "the angle of protection is
    /// pretty generous (around 90 degrees)".
    public static let halfArc: Float = .pi / 4

    /// True when `source` is inside the front arc of a holder at `holder` with yaw `facing`.
    /// A source on top of the holder counts as in front.
    public static func covers(
        holder: SIMD2<Float>, facing: Float, source: SIMD2<Float>
    ) -> Bool {
        let toward = source - holder
        guard simd_length(toward) > .ulpOfOne else { return true }
        let forward = SIMD2(cosf(facing), sinf(facing))
        return simd_dot(simd_normalize(toward), forward) >= cosf(halfArc)
    }
}
