public import OpenSkyFormatsESM

/// One `LIGH` shown at a point for a while; it fades out over its time.
nonisolated public struct FlashLight: Equatable, Sendable {
    public let light: ReferenceKey
    public let position: SIMD3<Float>
    public let duration: Float
    public var elapsed: Float = 0

    /// 1 at the start, 0 at the end; OpenSky's fade.
    public var strength: Float {
        duration > 0 ? max(0, 1 - elapsed / duration) : 0
    }

    public init(
        light: ReferenceKey,
        position: SIMD3<Float>,
        duration: Float,
        elapsed: Float = 0
    ) {
        self.light = light
        self.position = position
        self.duration = duration
        self.elapsed = elapsed
    }
}
