// How a material draws past its shading: depth test and write, decal depth bias,
// shadows, the distant-LOD role, and screen-door fading. Which shader flag sets
// each: docs/formats/nif-materials.md.

import Foundation

nonisolated public struct MaterialDrawState: Hashable, Sendable {
    public var depthTest = true
    public var depthWrite = true
    /// Drawn on top of another surface, so its depth is pulled toward the eye.
    public var decal = false
    public var castsShadows = true
    public var receivesShadows = true
    /// Terrain or object LOD: no sun shadows and no point lights.
    public var distantLOD = false
    /// Alpha is a dither pattern of whole pixels, not a blend.
    public var screenDoor = false
    /// SLSF2 Tree_Anim: the vertex alpha is the wind weight of a leaf, not opacity.
    public var windWeighted = false
    /// Alpha flag 0x8000: a placed reference's `XALP` cutoff replaces the test threshold.
    public var takesPlacedAlphaCutoff = false

    public init() {}

    public static let standard = MaterialDrawState()
}
