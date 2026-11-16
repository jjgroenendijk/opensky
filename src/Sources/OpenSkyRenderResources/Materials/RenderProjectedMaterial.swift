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
    /// `DrawUniforms.projectedColor`: the single-pass colour, or the overlay's normal
    /// dampener in x; the noise tile in w.
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
        let first = material.singlePass
            ? material.singlePassColor
            : SIMD3(material.normalDampener, 0, 0)
        color = SIMD4(first, material.noiseUVScale)
    }

    /// The `w` of `DrawUniforms.projectedParameters`, a sum of bits. The kind: 0 none,
    /// 1 the colour, 2 the single-pass texture, 3 the overlay texture. Under improved
    /// snow, 4 marks a snow material, 8 a snow mesh, 16 a mesh that is snow under the layer.
    public static func mode(
        _ projected: Self?,
        mesh: (isSnow: Bool, isSnowBase: Bool),
        texturesEnabled: Bool,
        improvedSnow: Bool
    ) -> Float {
        var bits: UInt32 = projected?.kind(texturesEnabled: texturesEnabled) ?? 0
        if improvedSnow {
            bits |= (projected?.isSnow == true && bits != 0) ? 4 : 0
            bits |= mesh.isSnow ? 8 : 0
            bits |= mesh.isSnowBase ? 16 : 0
        }
        return Float(bits)
    }

    /// An overlay without its model's texture has nothing to draw, as in the game.
    private func kind(texturesEnabled: Bool) -> UInt32 {
        if !singlePass {
            return diffuse != nil ? 3 : 0
        }
        return texturesEnabled && diffuse != nil ? 2 : 1
    }
}
