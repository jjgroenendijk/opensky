// A static's directional material, ready to bind (docs/rendering/surface-shading.md).

@preconcurrency @unsafe public import Metal
public import OpenSkyFormatsCore
import simd

nonisolated public struct RenderProjectedMaterial: Sendable {
    public let diffuse: any MTLTexture?
    public let noise: any MTLTexture?
    /// `DrawUniforms.projectedDirection`.
    public let direction: SIMD4<Float>
    /// `DrawUniforms.projectedParameters` without the mode in `w`.
    public let parameters: SIMD4<Float>
    /// `DrawUniforms.projectedColor`.
    public let color: SIMD4<Float>
    public let singlePass: Bool
    public let isSnow: Bool

    public init(_ material: ProjectedMaterial, diffuse: any MTLTexture?, noise: any MTLTexture?) {
        self.diffuse = diffuse
        self.noise = noise
        singlePass = material.singlePass
        isSnow = material.isSnow
        let angle = min(max(material.maxAngle, 0), 180) * .pi / 180
        direction = SIMD4(material.direction, cos(angle))
        // A single-pass texture repeats every two noise tiles, an overlay every material tile.
        let tile = material.singlePass ? material.noiseUVScale * 2 : material.materialUVScale
        parameters = SIMD4(material.falloffScale, material.falloffBias, tile, 0)
        color = SIMD4(material.singlePassColor, material.noiseUVScale)
    }

    /// The `w` of `DrawUniforms.projectedParameters`: 1 the colour, 2 the single-pass
    /// texture, 3 the overlay texture; 4 more marks snow.
    public func mode(texturesEnabled: Bool, improvedSnow: Bool) -> Float {
        let kind: Float = if !singlePass {
            diffuse != nil ? 3 : 1
        } else {
            texturesEnabled && diffuse != nil ? 2 : 1
        }
        return kind + (isSnow && improvedSnow ? 4 : 0)
    }
}
