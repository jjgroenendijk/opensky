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

/// A shot's muzzle flash: the `NAM1` model and the muzzle light, shown for `duration` s.
nonisolated public struct MuzzleFlash: Equatable, Sendable {
    public var model: String?
    public var light: ReferenceKey?
    public var duration: Float

    public init(model: String?, light: ReferenceKey?, duration: Float) {
        self.model = model
        self.light = light
        self.duration = duration
    }
}
