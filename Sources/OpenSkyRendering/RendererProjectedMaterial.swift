// The directional material of a placed static in the draw uniforms
// (docs/rendering/surface-shading.md).

import OpenSkyRenderResources
import simd

extension Renderer {
    /// `DrawUniforms.projectedParameters`; `w` 0 when the material has none.
    func projectedParameters(_ projected: RenderProjectedMaterial?) -> SIMD4<Float> {
        guard let projected else { return .zero }
        var parameters = projected.parameters
        parameters.w = projected.mode(texturesEnabled: projectedTexturesEnabled)
        return parameters
    }
}
