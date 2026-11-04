// The screen-space effects inside the image-space composite. They read the scene
// depth, so a frame with any of them on grades through the split pass, and the split
// copies the depth beside the colour (docs/rendering/post-effects.md).

import Metal
import OpenSkyRenderCore
import OpenSkyShaderTypes
import simd

/// The depth copy the composite reads; `copy` is nil when the frame has no effect on.
struct PostEffectDepthCopy {
    let copy: MTLTexture?
}

extension Renderer {
    /// Nil when no effect is on, or the frame has no perspective depth to read.
    func postEffectUniforms(
        _ parameters: ImageSpaceParameters,
        targetHeight: Int
    ) -> PostEffectUniforms? {
        guard postEffects.isActive, waterDepth.unproject != nil, !isRenderDebugActive
        else { return nil }
        let viewProjection = sceneProjection * frameInput.view.viewMatrix()
        var uniforms = PostEffectUniforms()
        uniforms.inverseViewProjection = viewProjection.inverse
        uniforms.projection = SIMD4(
            sceneProjection.columns.0.x, sceneProjection.columns.1.y, 0, 0
        )
        if postEffects.ambientOcclusion {
            uniforms.effects |= UInt32(PostEffectFlag.ambientOcclusion.rawValue)
            uniforms.ambientOcclusion = SIMD4(
                PostEffectSettings.ambientOcclusionRadius,
                PostEffectSettings.ambientOcclusionStrength,
                PostEffectSettings.ambientOcclusionBias, 0
            )
        }
        if postEffects.volumetricLight {
            uniforms.effects |= UInt32(PostEffectFlag.volumetricLight.rawValue)
            uniforms.volumetricLight = SIMD4(
                PostEffectSettings.volumetricStrength, Float(postEffects.volumetricSteps),
                PostEffectSettings.volumetricReach, PostEffectSettings.volumetricAsymmetry
            )
        }
        if postEffects.depthOfField, parameters.depthOfField.x > 0 {
            uniforms.effects |= UInt32(PostEffectFlag.depthOfField.rawValue)
            uniforms.depthOfField = SIMD4(
                parameters.depthOfField,
                PostEffectSettings.depthOfFieldRadius * Float(targetHeight) / 1080
            )
        }
        if postEffects.fxaa {
            uniforms.effects |= UInt32(PostEffectFlag.antiAliasing.rawValue)
        }
        if
            postEffects.lensFlare, let sky = frameCelestial,
            let sun = sunScreenPosition(viewProjection)
        {
            let strength = LensFlareMath.strength(sky)
            if strength > 0 {
                uniforms.effects |= UInt32(PostEffectFlag.lensFlare.rawValue)
                uniforms.lensFlare = SIMD4(sun.x, sun.y, strength, drawableAspectRatio)
            }
        }
        return uniforms.effects == 0 ? nil : uniforms
    }

    /// Outdoors under a sky only; nil when the sun is behind the camera or set.
    private func sunScreenPosition(_ viewProjection: float4x4) -> SIMD2<Float>? {
        guard frameCelestial != nil else { return nil }
        return LensFlareMath.sunScreenPosition(
            viewProjection: viewProjection, camera: frameInput.view.position,
            toSun: -exteriorSunTravelDirection
        )
    }

    /// Nil when the grade needs a depth copy and none can be made.
    func postEffectDepthCopy(
        _ grade: ImageSpaceGrade,
        descriptor: MTL4RenderPassDescriptor
    ) -> PostEffectDepthCopy? {
        guard grade.post != nil else { return PostEffectDepthCopy(copy: nil) }
        guard
            let depth = descriptor.depthAttachment.texture,
            let copy = keptCopy(matching: depth, at: \.postEffectDepth, label: "PostEffectDepth")
        else { return nil }
        return PostEffectDepthCopy(copy: copy)
    }
}
