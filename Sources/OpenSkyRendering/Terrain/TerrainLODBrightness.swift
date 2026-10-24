// The Creation Kit brightens terrain LOD textures when it builds them, and the game's
// landscape noise shader (type 18) darkens them again. Object LOD is not brightened.
// How much differs between worldspaces, so each one is fitted from its own data
// (docs/rendering/surface-shading.md).

import simd

/// The brightening curve on 0...1 gamma values: `brightened = gain * source^exponent`.
nonisolated public struct TerrainLODBrightness: Equatable, Sendable {
    public var gain: Float
    public var exponent: Float

    public init(gain: Float, exponent: Float) {
        self.gain = gain
        self.exponent = exponent
    }

    /// Tamriel as `fitted(samples:)` measures it on the user's install.
    public static let vanilla = Self(gain: 2.431, exponent: 1.145)
    /// Leaves the texture as it is, for when the noise term is off.
    public static let identity = Self(gain: 1, exponent: 1)

    public func brightened(_ source: Float) -> Float {
        min(gain * pow(max(source, 0), exponent), 1)
    }

    public func darkened(_ brightened: Float) -> Float {
        pow(max(brightened, 0) / gain, 1 / exponent)
    }

    /// Darkened over brightened for a typical land value (0.4 gamma).
    public var typicalFactor: Float {
        darkened(0.4) / 0.4
    }

    /// Keeps a fit over broken data from blacking out or washing out the land.
    static let gainRange: ClosedRange<Float> = 0.5 ... 4
    /// Fewer cells than this give the vanilla curve instead of a fit.
    public static let minimumSamples = 16

    /// Fits the gain of one worldspace's LOD with the vanilla exponent. Each sample
    /// is x = the cell's LAND brightness, y = its LOD texel brightness, in gamma.
    public static func fitted(samples: [SIMD2<Float>]) -> Self {
        let exponent = vanilla.exponent
        let gains = samples.filter { $0.x > 0.02 && $0.y > 0 }
            .map { $0.y / pow($0.x, exponent) }
            .sorted()
        guard gains.count >= minimumSamples else { return vanilla }
        let gain = min(max(gains[gains.count / 2], gainRange.lowerBound), gainRange.upperBound)
        return Self(gain: gain, exponent: exponent)
    }

    /// Rec. 709 weights, applied to gamma values like the measurement.
    public static func luminance(_ colour: SIMD3<Float>) -> Float {
        simd_dot(colour, SIMD3(0.2126, 0.7152, 0.0722))
    }

    /// x = gain, y = exponent, as `FrameUniforms.terrainLODBrightening` reads it.
    public var uniform: SIMD2<Float> {
        SIMD2(gain, exponent)
    }
}
