// How a tree moves in the wind, from its TREE `CNAM`: the sway of the whole tree and the
// flutter of its wind-weighted leaves. See docs/rendering/trees.md.

import OpenSkyFormatsESM

nonisolated public struct TreeMotion: Equatable, Sendable {
    /// Leaf values for a wind-weighted shape with no TREE record, the Creation Kit's
    /// suggested starting point.
    public static let defaultLeafAmplitude: Float = 3
    public static let defaultLeafFrequency: Float = 1

    public var sway: Float
    public var swayFrequency: Float
    public var leafAmplitude: Float
    public var leafFrequency: Float

    public init(sway: Float, swayFrequency: Float, leafAmplitude: Float, leafFrequency: Float) {
        self.sway = sway
        self.swayFrequency = swayFrequency
        self.leafAmplitude = leafAmplitude
        self.leafFrequency = leafFrequency
    }

    /// The sway is the mean of the front, back, and side amplitudes and frequencies.
    public init(_ data: ModelBaseDetails.TreeData) {
        func finite(_ value: Float) -> Float {
            value.isFinite ? max(value, 0) : 0
        }
        sway = finite((data.frontAmplitude + data.backAmplitude + data.sideAmplitude) / 3)
        swayFrequency = finite((data.frontFrequency + data.backFrequency + data.sideFrequency) / 3)
        leafAmplitude = finite(data.leafAmplitude)
        leafFrequency = finite(data.leafFrequency)
    }

    /// `DrawUniforms.windMotion` for one draw. Only a wind-weighted shape gets a leaf
    /// frequency, which tells the shader its vertex alpha is a weight.
    public static func uniform(_ motion: TreeMotion?, windWeighted: Bool) -> SIMD4<Float> {
        let leafFrequency = motion.map(\.leafFrequency).flatMap { $0 > 0 ? $0 : nil }
            ?? defaultLeafFrequency
        return SIMD4(
            motion?.sway ?? 0,
            motion?.swayFrequency ?? 0,
            windWeighted ? motion?.leafAmplitude ?? defaultLeafAmplitude : 0,
            windWeighted ? leafFrequency : 0
        )
    }
}
