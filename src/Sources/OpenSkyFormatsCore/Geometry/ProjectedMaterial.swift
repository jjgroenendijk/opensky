// A static's directional material: a `MATO` laid over the faces that point along its
// projection vector, such as snow on the tops of rocks. docs/formats/environment-shading.md
// has the record fields; docs/rendering/surface-shading.md the shading.

import Foundation
import simd

nonisolated public struct ProjectedMaterial: Hashable, Sendable {
    /// The game's shared projected map for a single-pass material, else the `MATO`
    /// model's first shape; nil draws the single-pass colour.
    public var diffuseTexture: String?
    /// Breaks up the layer's edge.
    public var noiseTexture: String?
    /// The world direction faces must point along, normalized.
    public var direction: SIMD3<Float>
    /// `STAT` `DNAM`: faces more than this many degrees from `direction` get none.
    public var maxAngle: Float
    public var falloffScale: Float
    public var falloffBias: Float
    public var noiseUVScale: Float
    public var materialUVScale: Float
    /// Linear 0...1 RGB: tints the single-pass texture, or is drawn alone.
    public var singlePassColor: SIMD3<Float>
    /// `MATO` `DATA` flags: drawn inside the shape's own shading, and snow.
    public var singlePass: Bool
    public var isSnow: Bool

    public init(
        diffuseTexture: String?,
        noiseTexture: String?,
        direction: SIMD3<Float>,
        maxAngle: Float,
        falloffScale: Float,
        falloffBias: Float,
        noiseUVScale: Float,
        materialUVScale: Float,
        singlePassColor: SIMD3<Float>,
        singlePass: Bool = true,
        isSnow: Bool = false
    ) {
        self.diffuseTexture = diffuseTexture
        self.noiseTexture = noiseTexture
        self.singlePass = singlePass
        self.isSnow = isSnow
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
        ].map { unsafe String(format: "%.4f", $0) }
        return "projected:\(diffuseTexture ?? "-"),\(noiseTexture ?? "-"),"
            + "\(singlePass ? 1 : 0)\(isSnow ? 1 : 0)," + numbers.joined(separator: ",")
    }
}
