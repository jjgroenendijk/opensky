// The screen-space effects the image-space composite draws, chosen by the game's
// graphics options. docs/rendering/post-effects.md has the effects and their values.

import Foundation

nonisolated public struct PostEffectSettings: Equatable, Sendable {
    /// `[Display] bSAOEnable`.
    public var ambientOcclusion = false

    public init() {}

    /// Whether the composite must read neighbour pixels and the scene depth.
    public var isActive: Bool {
        ambientOcclusion
    }

    /// The reach of an occluder in world units; unverified.
    public static let ambientOcclusionRadius: Float = 48
    /// How dark full occlusion gets; unverified.
    public static let ambientOcclusionStrength: Float = 1.2
    /// Ignores occluders closer to the surface plane than this share of their distance.
    public static let ambientOcclusionBias: Float = 0.05
}
