// The Creation Kit brightens terrain LOD textures when it builds them, and the game's
// landscape noise shader (type 18) darkens them again. Object LOD is not brightened.
// docs/rendering/surface-shading.md has the measurement behind the curve.

import simd

/// The brightening curve on 0...1 gamma values: `brightened = gain * source^exponent`.
nonisolated public struct TerrainLODBrightness: Equatable, Sendable {
    public var gain: Float
    public var exponent: Float

    public init(gain: Float, exponent: Float) {
        self.gain = gain
        self.exponent = exponent
    }

    /// Fitted on the user's install: vanilla LOD against the same land baked from LAND.
    public static let vanilla = Self(gain: 2.385, exponent: 1.145)
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

    /// x = gain, y = exponent, as `FrameUniforms.terrainLODBrightening` reads it.
    public var uniform: SIMD2<Float> {
        SIMD2(gain, exponent)
    }
}
