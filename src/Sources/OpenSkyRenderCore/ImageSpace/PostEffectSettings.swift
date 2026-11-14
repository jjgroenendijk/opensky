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
    /// The game's screen-space indirect light, off by default as in the game.
    public var indirectLight = false

    public init() {}

    /// Whether the composite must read neighbour pixels and the scene depth.
    public var isActive: Bool {
        ambientOcclusion || volumetricLight || depthOfField || lensFlare || fxaa || indirectLight
    }

    /// Cascade taps along each pixel's ray, by quality; unverified.
    public var volumetricSteps: Int {
        [8, 16, 32][min(max(volumetricQuality, 0), 2)]
    }

    /// The game's occluder reach in world units.
    public static let ambientOcclusionRadius: Float = 250
    /// The bias at the screen centre; it grows toward the edge and with depth.
    public static let ambientOcclusionBias: Float = 2.5
    /// The game divides its intensity 15 by the radius to the sixth power.
    public static let ambientOcclusionIntensity: Float = 15
    /// The game's contrast value 0.11 below 0.5 raises the occlusion to `2 × 0.11`.
    public static let ambientOcclusionContrastExponent: Float = 0.22
    /// The history weight falls by 0.3 for each unit the occlusion changed.
    public static let ambientOcclusionHistoryDifference: Float = 0.3
    /// The history weight falls by 200 for each 7000 units the depth changed.
    public static let ambientOcclusionHistoryDepth: Float = 200
    /// The game's indirect light reach in world units.
    public static let indirectLightRadius: Float = 100
    /// The game's strength is not known. 400 bounces about 0.3 of a lit wall into a corner.
    public static let indirectLightStrength: Float = 400
    /// The bias at the screen centre, as the occlusion's; the game's value is not known.
    public static let indirectLightBias: Float = 2.5
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
    /// The near plane of the game's depth buffer, `fNearDistance`, in world units. The
    /// volumetric slices are even in that buffer's depth raised to the sampling range.
    public static let volumetricNearPlane: Float = 15
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
