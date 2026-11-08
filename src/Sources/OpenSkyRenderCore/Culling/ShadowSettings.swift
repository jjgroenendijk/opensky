// The game's sun-shadow options, `[Display] fShadowDistance` and
// `iShadowMapResolution`, made safe for the shadow pass.

/// The shadow range and map size the player settings ask for.
nonisolated public struct ShadowSettings: Equatable, Sendable {
    public static let defaultResolution = 2048
    /// The game sets no top; 16384 is the largest Metal texture. The map costs
    /// 12 bytes a texel, so 16384 takes 3 GB.
    public static let resolutionRange = 512 ... 16384

    /// Nil keeps the renderer's own range.
    public let distance: Float?
    /// A power of two in `resolutionRange`.
    public let resolution: Int

    public init() {
        distance = nil
        resolution = Self.defaultResolution
    }

    /// 0 or a value that is not finite keeps the default of that field.
    public init(distance: Double, resolution: Double) {
        self.distance = distance.isFinite && distance > 0 ? Float(min(distance, 65536)) : nil
        self.resolution = Self.resolution(resolution)
    }

    /// The largest power of two at or below `value`, inside `resolutionRange`.
    static func resolution(_ value: Double) -> Int {
        guard value.isFinite, value >= 1 else { return defaultResolution }
        let clamped = min(
            max(Int(min(value, 1e6)), resolutionRange.lowerBound),
            resolutionRange.upperBound
        )
        return 1 << (Int.bitWidth - 1 - clamped.leadingZeroBitCount)
    }
}
