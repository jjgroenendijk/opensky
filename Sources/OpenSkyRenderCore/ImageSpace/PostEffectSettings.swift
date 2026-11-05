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
    /// `[ImageSpace] bLensFlare`.
    public var lensFlare = false
    /// `[Display] bFXAAEnabled`.
    public var fxaa = false

    public init() {}

    /// Whether the composite must read neighbour pixels and the scene depth.
    public var isActive: Bool {
        ambientOcclusion || volumetricLight || depthOfField || lensFlare || fxaa
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
    /// Past this distance depth precision makes the normals noisy, so occlusion fades
    /// out by here; unverified.
    public static let ambientOcclusionFadeDistance: Float = 4096
    /// The full blur in pixels of a 1080-pixel-high frame for a Creation Kit "Blur
    /// Radius" of 0 to 7; unverified.
    public static func depthOfFieldPixels(blurRadius: Float) -> Float {
        2 + 2 * blurRadius
    }

    /// How bright the flare ghosts get; unverified.
    public static let lensFlareStrength: Float = 0.6
    /// How bright the lit air gets for each unit of `VOLI` intensity; unverified.
    public static let volumetricStrengthPerIntensity: Float = 0.025
    /// World units the ray reaches for each unit of `VOLI` sampling range; unverified.
    public static let volumetricReachPerSamplingRange: Float = 102.4
    /// World units of one density noise cell for each unit of `VOLI` density size;
    /// unverified.
    public static let volumetricCellPerDensitySize: Float = 64
    /// World units per second the noise drifts for each unit of `VOLI` wind speed;
    /// unverified.
    public static let volumetricDriftPerWindSpeed: Float = 4
    /// World units per second the noise falls for each unit of `VOLI` falling speed;
    /// unverified.
    public static let volumetricFallPerFallingSpeed: Float = 64
}
