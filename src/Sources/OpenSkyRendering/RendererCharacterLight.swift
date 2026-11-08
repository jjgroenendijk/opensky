// The game's character light: white light on every lit shape of an actor, from a fixed
// facing direction and a fill from below, scaled by the scene's luminance
// (docs/rendering/surface-shading.md#character-light).

import OpenSkyRenderCore

extension Renderer {
    /// The facing and fill weights of the game's character light.
    static let characterLightWeights = SIMD2<Float>(0.75, 0.3)

    /// The game scales the light by twice the scene luminance, at most 0.75.
    public var characterLightUniform: SIMD4<Float> {
        guard characterLightEnabled else { return .zero }
        let luminance = eyeAdaptation.adaptedLuminance ?? EyeAdaptation.key
        let strength = min(max(2 * luminance, 0), 0.75)
        return SIMD4(lowHalf: Self.characterLightWeights, highHalf: SIMD2(strength, 0))
    }
}
