// The directional material of a placed static in the draw uniforms
// (docs/rendering/surface-shading.md).

import OpenSkyRenderResources
import simd

extension Renderer {
    /// `DrawUniforms.projectedParameters`; `w` 0 when the shape has no directional
    /// material and is not snow.
    func projectedParameters(_ surface: RenderSurfaceMaterial) -> SIMD4<Float> {
        var parameters = surface.projected?.parameters ?? .zero
        parameters.w = RenderProjectedMaterial.mode(
            surface.projected,
            mesh: (surface.isSnow, surface.isSnowBase),
            texturesEnabled: surfaceFeatures.projectedTextures,
            improvedSnow: surfaceFeatures.improvedSnow
        )
        return parameters
    }
}
