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

    public init() {}

    public static let standard = MaterialDrawState()
}
