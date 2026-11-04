// A static's directional material, ready to bind (docs/rendering/surface-shading.md).

@preconcurrency import Metal
import OpenSkyFormatsCore
import simd

nonisolated public struct RenderProjectedMaterial: Sendable {
    public let diffuse: MTLTexture?
    public let normal: MTLTexture?
    /// `DrawUniforms.projectedDirection`.
    public let direction: SIMD4<Float>
    /// `DrawUniforms.projectedParameters` without the mode in `w`.
    public let parameters: SIMD4<Float>
    /// `DrawUniforms.projectedColor`.
    public let color: SIMD4<Float>

    public init(_ material: ProjectedMaterial, diffuse: MTLTexture?, normal: MTLTexture?) {
        self.diffuse = diffuse
        self.normal = normal
        let angle = min(max(material.maxAngle, 0), 180) * .pi / 180
        direction = SIMD4(material.direction, cos(angle))
        parameters = SIMD4(
            material.falloffScale, material.falloffBias, material.materialUVScale, 0
        )
        color = SIMD4(material.singlePassColor, material.noiseUVScale)
    }

    /// The `w` of `DrawUniforms.projectedParameters`: 2 draws the textures, 1 the colour.
    public func mode(texturesEnabled: Bool) -> Float {
        texturesEnabled && diffuse != nil ? 2 : 1
    }
}
