// A static's directional material: a `MATO` laid over the faces that point along its
// projection vector, such as snow on the tops of rocks. docs/formats/environment-shading.md
// has the record fields; docs/rendering/surface-shading.md the shading.

import Foundation
import simd

nonisolated public struct ProjectedMaterial: Hashable, Sendable {
    /// From the `MATO` model's first shape; nil draws the single-pass colour.
    public var diffuseTexture: String?
    public var normalTexture: String?
    /// The world direction faces must point along, normalized.
    public var direction: SIMD3<Float>
    /// `STAT` `DNAM`: faces more than this many degrees from `direction` get none.
    public var maxAngle: Float
    public var falloffScale: Float
    public var falloffBias: Float
    public var noiseUVScale: Float
    public var materialUVScale: Float
    /// Linear 0...1 RGB, drawn instead of the textures.
    public var singlePassColor: SIMD3<Float>

    public init(
        diffuseTexture: String?,
        normalTexture: String?,
        direction: SIMD3<Float>,
        maxAngle: Float,
        falloffScale: Float,
        falloffBias: Float,
        noiseUVScale: Float,
        materialUVScale: Float,
        singlePassColor: SIMD3<Float>
    ) {
        self.diffuseTexture = diffuseTexture
        self.normalTexture = normalTexture
        let length = simd_length(direction)
        self.direction = length > 0 ? direction / length : SIMD3(0, 0, 1)
        self.maxAngle = maxAngle
        self.falloffScale = falloffScale
        self.falloffBias = falloffBias
        self.noiseUVScale = noiseUVScale
        self.materialUVScale = materialUVScale
        self.singlePassColor = singlePassColor
    }

    /// Part of a mesh cache key.
    public var cacheKey: String {
        let numbers = [
            direction.x, direction.y, direction.z, maxAngle, falloffScale, falloffBias,
            noiseUVScale, materialUVScale, singlePassColor.x, singlePassColor.y, singlePassColor.z
        ].map { String(format: "%.4f", $0) }
        return "projected:\(diffuseTexture ?? "-"),\(normalTexture ?? "-"),"
            + numbers.joined(separator: ",")
    }
}
