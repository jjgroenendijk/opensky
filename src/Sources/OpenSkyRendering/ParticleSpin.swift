// How a particle's spin angle advances. See docs/formats/nif-particles.md, "Rotation".

/// The game's wrap of a spin angle, in radians.
nonisolated enum ParticleSpin {
    /// The angle after one update. Above 10 pi it starts again at 0; otherwise a whole
    /// turn comes off once it passes 2 pi. A negative angle is never wrapped.
    static func advanced(_ angle: Float, by step: Float) -> Float {
        let next = angle + step
        if next > 10 * .pi {
            return 0
        }
        return next > 2 * .pi ? next - 2 * .pi : next
    }
}
