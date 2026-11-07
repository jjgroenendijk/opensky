// The screen-space effects inside the image-space composite. They read the scene
// depth, so a frame with any of them on grades through the split pass, and the split
// copies the depth beside the colour (docs/rendering/post-effects.md).

import Metal
import OpenSkyRenderCore
import OpenSkyShaderTypes
import simd

/// The depth copy the composite reads; `copy` is nil when the frame has no effect on.
struct PostEffectDepthCopy {
    let copy: any MTLTexture?
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
                0,
                PostEffectSettings.ambientOcclusionBias,
                PostEffectSettings.ambientOcclusionFadeDistance
            )
            setHistoryCamera(&uniforms)
        }
        if postEffects.indirectLight {
            uniforms.effects |= UInt32(PostEffectFlag.indirectLight.rawValue)
            setHistoryCamera(&uniforms)
            uniforms.indirectLight = SIMD4(
                PostEffectSettings.indirectLightRadius, PostEffectSettings.indirectLightStrength,
                PostEffectSettings.indirectLightBias, 0
            )
        }
        if postEffects.volumetricLight {
            uniforms.effects |= UInt32(PostEffectFlag.volumetricLight.rawValue)
            setVolumetricLight(&uniforms)
        }
        if postEffects.depthOfField, parameters.depthOfField.x > 0 {
            uniforms.effects |= UInt32(PostEffectFlag.depthOfField.rawValue)
            let pixels = PostEffectSettings
                .depthOfFieldPixels(blurRadius: parameters.depthOfFieldBlurRadius)
            uniforms.depthOfField = SIMD4(
                parameters.depthOfField, pixels * Float(targetHeight) / 1080
            )
            uniforms.depthOfFieldMode = SIMD4(
                parameters.depthOfFieldKeepsSkySharp ? 0 : 1,
                Float(parameters.depthOfFieldSides.rawValue),
                parameters.depthOfFieldUsesTarget ? 1 : 0, depthOfFieldFocus.centreWeight
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

    /// The camera and last frame's view, so the trace finds the pixel in its history.
    private func setHistoryCamera(_ uniforms: inout PostEffectUniforms) {
        let camera = frameInput.view.position
        uniforms.camera = SIMD4(camera, Float(frameIndex % 1024))
        uniforms.previousViewProjection = imageSpacePass.previousViewProjection ?? .init(1)
        uniforms.previousCamera = SIMD4(imageSpacePass.previousCamera ?? camera, 0)
        let reach = PostEffectSettings.ambientOcclusionRadius
        let reachSquared = reach * reach
        uniforms.ambientOcclusionCurve = SIMD4(
            PostEffectSettings
                .ambientOcclusionIntensity / (reachSquared * reachSquared * reachSquared),
            PostEffectSettings.ambientOcclusionContrastExponent,
            PostEffectSettings.ambientOcclusionHistoryDifference,
            PostEffectSettings.ambientOcclusionHistoryDepth
        )
    }

    /// Traces the occlusion and the indirect light the composite reads, after the scene
    /// copies. Each pass uses its history only when last frame traced into it.
    func encodeHistoryPasses(
        _ encoder: any MTL4ComputeCommandEncoder,
        post: inout PostEffectUniforms?,
        inputs: (depth: any MTLTexture, scene: any MTLTexture),
        slot: Int
    ) {
        guard var uniforms = post else { return }
        let passes = [
            HistoryPassEntry(
                pass: imageSpacePass.occlusion, flag: .ambientOcclusion, index: .postOcclusion
            ),
            HistoryPassEntry(
                pass: imageSpacePass.indirectLight, flag: .indirectLight, index: .postIndirectLight
            )
        ]
        let ready = passes.filter { entry in
            guard uniforms.effects & UInt32(entry.flag.rawValue) != 0 else { return false }
            guard entry.pass.prepare(matching: inputs.scene, residency: residencySet) else {
                uniforms.effects &= ~UInt32(entry.flag.rawValue)
                return false
            }
            let holds: Float = entry.pass.historyHolds(frame: frameIndex) ? 1 : 0
            if entry.flag == .ambientOcclusion {
                uniforms.previousCamera.w = holds
            } else {
                uniforms.indirectLight.w = holds
            }
            return true
        }
        post = uniforms
        guard !ready.isEmpty else { return }
        encoder.barrier(
            afterEncoderStages: .blit, beforeEncoderStages: .dispatch, visibilityOptions: .device
        )
        let address = imageSpacePass.postUniformBuffer.gpuAddress
            + UInt64(ImageSpacePassResources.postUniformStride * slot)
        let traced = PostHistoryInputs(uniforms: address, depth: inputs.depth, scene: inputs.scene)
        for entry in ready {
            entry.pass.encode(encoder, inputs: traced, frame: frameIndex)
            if let result = entry.pass.result {
                argumentTable.setTexture(result.gpuResourceID, index: entry.index.rawValue)
            }
        }
    }

    /// The weather's `VOLI` values (docs/rendering/post-effects.md#volumetric-light).
    private func setVolumetricLight(_ uniforms: inout PostEffectUniforms) {
        let look = volumetricLight.clamped
        uniforms.volumetricLight = SIMD4(
            PostEffectSettings.volumetricStrengthPerIntensity * look.intensity,
            Float(postEffects.volumetricSteps),
            PostEffectSettings.volumetricReachPerSamplingRange * look.samplingRangeFactor,
            look.phaseFunctionScattering
        )
        // The frame's sun colour carries the image space sunlight scale, which only the
        // lit shaders take; the weight undoes it.
        let sunlight = max(lightScales.sunlight, 0.001)
        uniforms.volumetricColour = SIMD4(
            look.color * look.customColorContribution,
            (1 - look.customColorContribution) / sunlight
        )
        uniforms.volumetricDensity = SIMD4(
            look.densityContribution,
            PostEffectSettings.volumetricCellPerDensitySize * look.densitySize,
            PostEffectSettings.volumetricDriftPerWindSpeed * look.densityWindSpeed,
            PostEffectSettings.volumetricFallPerFallingSpeed * look.densityFallingSpeed
        )
        uniforms.volumetricPhase = SIMD4(look.phaseFunctionContribution, 0, 0, 0)
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

/// One traced pass the composite reads: its switch and the slot its result binds to.
private struct HistoryPassEntry {
    let pass: PostHistoryPass
    let flag: PostEffectFlag
    let index: TextureIndex
}
