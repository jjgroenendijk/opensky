// The screen-space effects the image-space composite draws, chosen by the game's
// graphics options. docs/rendering/post-effects.md has the effects and their values.

import Foundation

nonisolated public struct PostEffectSettings: Equatable, Sendable {
    /// `[Display] bSAOEnable`.
    public var ambientOcclusion = false
    /// `[Display] bVolumetricLightingEnable`.
    public var volumetricLight = false
    /// `[Display] iVolumetricLightingQuality`: 0 low, 1 medium, 2 high.
    public var volumetricQuality = 1
    /// `[ImageSpace] bDoDepthOfField`: the image space's `DNAM` focus blur.
    public var depthOfField = false

    public init() {}

    /// Whether the composite must read neighbour pixels and the scene depth.
    public var isActive: Bool {
        ambientOcclusion || volumetricLight || depthOfField
    }

    /// Cascade taps along each pixel's ray, by quality; unverified.
    public var volumetricSteps: Int {
        [8, 16, 32][min(max(volumetricQuality, 0), 2)]
    }

    /// The reach of an occluder in world units; unverified.
    public static let ambientOcclusionRadius: Float = 48
    /// How dark full occlusion gets; unverified.
    public static let ambientOcclusionStrength: Float = 1.2
    /// Ignores occluders closer to the surface plane than this share of their distance.
    public static let ambientOcclusionBias: Float = 0.05
    /// The depth of field blur radius at full strength, in pixels of a 1080-pixel-high
    /// frame; unverified.
    public static let depthOfFieldRadius: Float = 8
    /// How bright the lit air gets; unverified.
    public static let volumetricStrength: Float = 0.05
    /// The ray stops here, in world units; the air gets no thicker past it.
    public static let volumetricReach: Float = 4096
    /// Henyey-Greenstein asymmetry: above 0 scatters most light toward the sun.
    public static let volumetricAsymmetry: Float = 0.6
}
