import Metal
import MetalKit
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRenderCore
import OpenSkyRenderResources
import OpenSkyShaderTypes
import simd

extension Renderer {
    /// Mutable state threaded through one scene pass's encoders: the open
    /// encoder + frame slot + frustum, the running cursors into the
    /// per-draw uniform ring (visible groups) and the per-instance
    /// transform ring (visible instances), and the accumulating draw stats.
    public struct ScenePassState {
        public let encoder: MTL4RenderCommandEncoder
        public let slot: Int
        public let frustum: Frustum
        /// The fill mode this frame's geometry draws under — `.lines` in the
        /// wireframe debug view. Encoded once at the top of the pass; the
        /// billboard layer forces `.fill` and restores this value, because a
        /// wireframed particle quad is noise rather than diagnosis.
        public var fillMode = MTLTriangleFillMode.fill
        public var drawCursor = 0
        public var instanceCursor = 0
        public var stats = SceneDrawStats()
        /// The scene list `encode(groups:)` draws, so the GPU-culled groups take the
        /// indirect path. Nil for lists outside the scene.
        var cullList: GPUCullList?
        /// Set while a scene list draws: each group then sets its material's depth flags.
        var materialDepth: MaterialDepthMode?
        /// Set while the blood of one weapon draws; weapon-blood groups draw only then.
        var weaponBloodAlpha: Float?
    }

    /// Writes this frame's uniforms into its 256-byte-aligned slot and
    /// returns the byte offset of that slot. `viewProjection` is computed by
    /// the caller (encodeScenePass shares it with the frustum). Sun/ambient
    /// come from the injected SceneCamera.
    private func updateFrameUniforms(slot: Int, viewProjection: float4x4) -> Int {
        let offset = Self.alignedFrameUniformsSize * slot
        let interiorLighting = activeLighting
        // Weather is an exterior-only source: interiors keep their own baked
        // CELL/LGTM lighting untouched (weatherLight nil there). The sky
        // palette applies only when the scene actually draws a sky.
        let weatherLight = interiorLighting == nil ? frameInput.weather : nil
        let covered = effects.loadingCover != nil
        let weatherSky = scene.sky != nil && !covered ? weatherLight : nil
        let ambient = weatherLight?.directionalAmbient
            ?? interiorLighting?.directionalAmbient ?? .black
        let fog = resolveFrameFog(weatherLight: covered ? nil : weatherLight)
        let grassDistance = clampedGrassDrawDistance
        var uniforms = FrameUniforms(
            viewProjectionMatrix: viewProjection,
            cameraPosition: frameInput.view.position,
            sunDirection: interiorLighting?.directionalDirection ?? camera.sunDirection,
            sunColor: weatherLight?.sunlightColor
                ?? interiorLighting?.directionalColor ?? camera.sunColor,
            ambientColor: weatherLight?.ambientColor
                ?? interiorLighting?.ambientColor ?? camera.ambientColor,
            directionalAmbientPositiveX: ambient.positiveX,
            directionalAmbientNegativeX: ambient.negativeX,
            directionalAmbientPositiveY: ambient.positiveY,
            directionalAmbientNegativeY: ambient.negativeY,
            directionalAmbientPositiveZ: ambient.positiveZ,
            directionalAmbientNegativeZ: ambient.negativeZ,
            fogNearColor: fog.nearColor,
            fogFarColor: fog.farColor,
            fogDistances: fog.distances,
            fogEnabled: fog.enabled,
            timeOfDayHours: frameInput.timeOfDay,
            animationTime: animationTime,
            shadowViewProjections: (
                shadowCascadeMatrix(0), shadowCascadeMatrix(1), shadowCascadeMatrix(2)
            ),
            shadowCascadeSplits: shadowCascadeSplitBounds(),
            cameraForward: frameInput.view.forward,
            shadowsEnabled: shadowsActiveThisFrame ? 1 : 0,
            shadowInverseResolution: 1 / Float(ShadowConstant.mapResolution.rawValue),
            shadowSampleRadius: shadowSampleRadius,
            weatherSkyEnabled: weatherSky == nil ? 0 : 1,
            weatherSkyUpperColor: weatherSky?.skyUpper ?? .zero,
            weatherSkyLowerColor: weatherSky?.skyLower ?? .zero,
            weatherHorizonColor: weatherSky?.horizon ?? .zero,
            weatherSunColor: weatherSky?.sun ?? .zero,
            weatherGlareColor: weatherSky?.sunGlare ?? .zero,

            cameraRight: frameInput.view.right,
            cameraUp: simd_normalize(simd_cross(frameInput.view.right, frameInput.view.forward)),
            grassWind: frameInput.wind.direction * frameInput.wind.speed
                * simd_clamp(grassWindScale, 0, GrassRenderPolicy.maximumWindScale),
            grassFadeDistances: SIMD2(
                max(grassDistance * 0.7, GrassRenderPolicy.minimumDrawDistance * 0.5),
                grassDistance
            ),
            debugMode: renderDebug.mode.rawValue,
            shadingTerms: shadingTerms.rawValue,
            sceneDepthUnproject: sceneDepthUnproject,
            terrainLODBrightening: terrainLODBrightness.uniform
        )
        frameUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<FrameUniforms>.size)
        return offset
    }

    /// Writes one group's material scalars into the ring and returns the
    /// byte offset. Ring stride is the (possibly regrown) slot capacity,
    /// not drawCount. Matrices live per instance (writeVisibleInstances).
    private func updateDrawUniforms(
        slot: Int,
        draw: Int,
        group: DrawGroup,
        pointLightCount: Int,
        alphaScale: Float
    ) -> Int {
        let offset = Self.alignedDrawUniformsSize * (slot * drawUniformSlotCapacity + draw)
        let material = group.material
        let effect = material.effect
        var uniforms = DrawUniforms(
            uvOffset: material.uvOffset,
            uvScale: material.uvScale,
            materialAlpha: material.alpha * alphaScale,
            alphaThreshold: material.alphaTestThreshold ?? 0,
            pointLightCount: UInt32(pointLightCount),
            receivesShadows: group.receivesShadows ? 1 : 0,
            layerCategory: group.layer.rawValue,
            // Only the blended pass runs after the scene depth copy, so only it fades soft.
            effectFlags: (effect?.flags ?? 0)
                & (group.drawsBlended ? ~0 : ~UInt32(EffectFlag.soft.rawValue)),
            effectBaseColor: effect?.baseColor ?? .zero,
            effectFalloff: effect?.falloff ?? .zero,
            effectBaseColorScale: effect?.baseColorScale ?? 1,
            effectSoftDepth: effect?.softDepth ?? 0,
            effectLightingInfluence: effect?.lightingInfluence ?? 0,
            additiveBlend: UInt32(material.additiveBlend?.rawValue ?? 0),
            materialFlags: material.surface.flags,
            specular: material.surface.specular,
            emissive: material.surface.emissive,
            lightingEffects: material.surface.lightingEffects,
            tintColor: material.surface.tintColor,
            multiLayer: material.surface.multiLayer
        )
        drawUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<DrawUniforms>.size)
        return offset
    }

    private var clampedGrassDrawDistance: Float {
        simd_clamp(
            grassDrawDistance,
            GrassRenderPolicy.minimumDrawDistance,
            GrassRenderPolicy.maximumDrawDistance
        )
    }

    /// Writes the group's frustum-surviving instance transforms tightly
    /// packed from the current instance cursor; returns the visible count
    /// and the byte offset the group's draw binds the transform ring at.
    /// Total written per frame <= scene.instanceCount <= ring capacity.
    private func writeVisibleInstances(
        of group: DrawGroup,
        state: inout ScenePassState
    ) -> (written: Int, byteOffset: Int) {
        let stride = MemoryLayout<InstanceTransform>.stride
        let base = state.slot * instanceSlotCapacity + state.instanceCursor
        var written = 0
        for placed in group.instances {
            // The live pose of a reference a rigid body owns, and the baked one
            // for everything else (RendererDynamicPose.swift).
            let instance = drawn(placed)
            if roomCulling.visibility?.contains(room: instance.room) == false {
                state.stats.culledInstances += 1
                state.stats.roomCulledInstances += 1
                continue
            }
            if let bounds = instance.bounds, !state.frustum.intersects(bounds) {
                state.stats.culledInstances += 1
                continue
            }
            var transforms = InstanceTransform(
                modelMatrix: instance.modelMatrix,
                normalMatrix: instance.normalMatrix,
                instanceColor: instance.instanceColor(regions: regionEmittance),
                grassParameters: .zero
            )
            instanceTransformBuffer.contents()
                .advanced(by: (base + written) * stride)
                .copyMemory(from: &transforms, byteCount: MemoryLayout<InstanceTransform>.size)
            written += 1
        }
        state.instanceCursor += written
        state.stats.drawnInstances += written
        return (written, base * stride)
    }

    /// The pipelines one `encode(groups:)` call picks from, by mesh kind.
    public struct GroupPipelines {
        public let staticMesh: MTLRenderPipelineState
        public let skinned: MTLRenderPipelineState
        public let morphedSkinned: MTLRenderPipelineState

        /// Debug channels replace the shaded surface for every geometry path at
        /// once, so the shipping set is swapped here rather than at each caller.
        func resolved(debug: DebugRenderPipelines?) -> Self {
            guard let debug else { return self }
            return Self(
                staticMesh: debug.staticMesh, skinned: debug.skinned,
                morphedSkinned: debug.morphedSkinned
            )
        }

        func pipeline(for group: DrawGroup) -> MTLRenderPipelineState {
            group.faceMorph != nil ? morphedSkinned
                : (group.mesh.isSkinned ? skinned : staticMesh)
        }
    }

    /// Encodes instanced draw groups: cull per instance, write visible transforms, bind
    /// the ring at the group offset, draw once. Empty groups encode nothing. Internal,
    /// so the first-person arms use the same path. `skippingBlended` leaves the
    /// blended groups to `encodeBlendedGroups`.
    public func encode(
        groups: [DrawGroup],
        staticPipeline: MTLRenderPipelineState,
        skinnedPipeline: MTLRenderPipelineState,
        morphedSkinnedPipeline: MTLRenderPipelineState,
        skippingBlended: Bool = false,
        state: inout ScenePassState
    ) {
        let pipelines = GroupPipelines(
            staticMesh: staticPipeline, skinned: skinnedPipeline,
            morphedSkinned: morphedSkinnedPipeline
        ).resolved(debug: isRenderDebugActive ? debugPipelines : nil)
        let layers = effectiveRenderLayers
        // Pipeline bound lazily: an all-culled list encodes nothing. Model
        // ordering is retained, so switch only when rigid/skinned kind does.
        var boundPipeline: ObjectIdentifier?
        for (index, group) in groups.enumerated() where layers.contains(group.layer) {
            guard !skippingBlended || !(group.drawsBlended || group.drawsRefraction) else {
                continue
            }
            encode(
                group: group, at: index, pipelines: pipelines,
                boundPipeline: &boundPipeline, state: &state
            )
        }
    }

    /// Draws one group; `index` is its place in the list the cull pass saw.
    func encode(
        group: DrawGroup,
        at index: Int,
        pipelines: GroupPipelines,
        boundPipeline: inout ObjectIdentifier?,
        state: inout ScenePassState
    ) {
        guard
            !group.isWeaponBlood || state.weaponBloodAlpha != nil,
            let visible = visibleInstances(of: group, at: index, state: &state)
        else { return }
        let pipeline = pipelines.pipeline(for: group)
        if boundPipeline != ObjectIdentifier(pipeline) {
            state.encoder.setRenderPipelineState(pipeline)
            boundPipeline = ObjectIdentifier(pipeline)
        }
        // Running visible-group cursor indexes the uniform ring:
        // visible groups <= scene.drawCount <= ring capacity.
        let lightOffset = group.instances.first?.receivesPointLights == true
            ? writePointLights(near: group.lightingCenter, slot: state.slot, draw: state.drawCursor)
            : PointLightRange()
        let uniformOffset = updateDrawUniforms(
            slot: state.slot,
            draw: state.drawCursor,
            group: group,
            // An effect shape takes no light from a shadow-casting light.
            pointLightCount: group.material.effect == nil
                ? lightOffset.count : lightOffset.unshadowedCount,
            alphaScale: state.weaponBloodAlpha ?? 1
        )
        state.drawCursor += 1
        state.stats.drawCalls += 1
        argumentTable.setAddress(
            group.mesh.vertexBuffer.gpuAddress,
            index: BufferIndex.vertices.rawValue
        )
        bindSkinningBuffers(for: group.mesh, slot: state.slot)
        bindFaceMorph(group.faceMorph, slot: state.slot)
        argumentTable.setAddress(
            drawUniformBuffer.gpuAddress + UInt64(uniformOffset),
            index: BufferIndex.drawUniforms.rawValue
        )
        argumentTable.setAddress(visible.address, index: BufferIndex.instanceTransforms.rawValue)
        argumentTable.setAddress(
            pointLightBuffer.gpuAddress + UInt64(lightOffset.byteOffset),
            index: BufferIndex.pointLights.rawValue
        )
        bindMaterialTextures(group.material)
        if let mode = state.materialDepth {
            applyDrawState(of: group.material, mode: mode, state: state)
        }
        state.encoder.setCullMode(group.material.doubleSided ? .none : .back)
        state.encoder.drawInstances(of: group.mesh, visible)
    }

    /// The fragment declares every surface slot, so the diffuse fills a 2D slot and
    /// the black cube the environment slot when a material lacks the texture.
    private func bindMaterialTextures(_ material: RenderMaterial) {
        let diffuse = streamedBinding(material.diffuse)
        argumentTable.setTexture(diffuse, index: TextureIndex.diffuse.rawValue)
        argumentTable.setTexture(
            material.effect?.palette?.gpuResourceID ?? diffuse,
            index: TextureIndex.effectPalette.rawValue
        )
        let surface = material.surface
        let slots: [(MTLTexture?, TextureIndex)] = [
            (material.normal, .surfaceNormal),
            (surface.glow, .surfaceGlow),
            (surface.detail, .surfaceDetail),
            (surface.environmentMask, .surfaceEnvironmentMask),
            (material.faceTint ?? surface.innerLayer, .surfaceLayer),
            (surface.backLight, .surfaceBackLight)
        ]
        for (texture, index) in slots {
            argumentTable.setTexture(texture.map(streamedBinding) ?? diffuse, index: index.rawValue)
        }
        argumentTable.setTexture(
            (surface.environment ?? blackCube).gpuResourceID,
            index: TextureIndex.surfaceEnvironment.rawValue
        )
        argumentTable.setTexture(
            (material.effect?.sourceVolume ?? greyVolume).gpuResourceID,
            index: TextureIndex.effectSourceVolume.rawValue
        )
        argumentTable.setTexture(
            refraction.copy?.gpuResourceID ?? diffuse,
            index: TextureIndex.sceneColor.rawValue
        )
    }

    /// The group's surviving instances for the camera, or nil when none survive.
    private func visibleInstances(
        of group: DrawGroup,
        at index: Int,
        state: inout ScenePassState
    ) -> VisibleInstances? {
        switch gpuVisibility(
            of: index, in: state.cullList, view: 0, slot: state.slot, frustum: state.frustum
        ) {
        case .skipped:
            return nil
        case let .drawn(visible):
            return visible
        case .cpu:
            let run = writeVisibleInstances(of: group, state: &state)
            guard run.written > 0 else { return nil }
            return .packed(
                count: run.written,
                address: instanceTransformBuffer.gpuAddress + UInt64(run.byteOffset)
            )
        }
    }

    private func bindSkinningBuffers(for mesh: RenderMesh, slot: Int) {
        guard
            let skinning = mesh.skinningBuffer,
            let matrices = mesh.boneMatrixBuffer
        else { return }
        argumentTable.setAddress(
            skinning.gpuAddress,
            index: BufferIndex.skinningAttributes.rawValue
        )
        argumentTable.setAddress(
            matrices.gpuAddress + UInt64(mesh.boneMatrixOffset(slot: slot)),
            index: BufferIndex.boneMatrices.rawValue
        )
        prepareBoneMatricesOnce(for: mesh, slot: slot)
    }

    /// Copies a skinned mesh's palette into this frame's slot at most once —
    /// the shadow and scene passes both bind skinned casters, but the CPU
    /// palette is identical across both within one frame, so a second copy is
    /// pure waste. frameBonePrepared resets at the top of each frame's encode.
    public func prepareBoneMatricesOnce(for mesh: RenderMesh, slot: Int) {
        guard frameBonePrepared.insert(ObjectIdentifier(mesh)).inserted else { return }
        mesh.prepareBoneMatrices(slot: slot)
    }

    /// The frame-wide bindings every draw in the pass shares: this frame's
    /// uniform slot, the world sampler, and the shadow cascade array with its
    /// compare sampler (bound even with shadows off so validation stays clean).
    func bindScenePassFrameArguments(
        encoder: MTL4RenderCommandEncoder,
        frameOffset: Int
    ) {
        encoder.label = "Static Mesh Encoder"
        encoder.setFrontFacing(.counterClockwise)
        // The object and mesh stages draw mesh-shader grass.
        encoder.setArgumentTable(argumentTable, stages: [.vertex, .fragment, .object, .mesh])
        argumentTable.setAddress(
            frameUniformBuffer.gpuAddress + UInt64(frameOffset),
            index: BufferIndex.frameUniforms.rawValue
        )
        argumentTable.setSamplerState(
            sampler.gpuResourceID,
            index: SamplerIndex.trilinear.rawValue
        )
        argumentTable.setTexture(
            shadow.map.gpuResourceID,
            index: TextureIndex.shadowMap.rawValue
        )
        argumentTable.setSamplerState(
            shadow.sampler.gpuResourceID,
            index: SamplerIndex.shadowCompare.rawValue
        )
        bindRayTracedScene(argumentTable)
    }

    /// The opaque groups, the terrain, and the alpha-tested groups, in that order.
    private func encodeSceneGeometry(state: inout ScenePassState) {
        state.cullList = .opaque
        state.materialDepth = .writes
        let rayTraced = rayTracedPipelines
        encode(
            groups: frameDrawGroups.opaque,
            staticPipeline: rayTraced?.opaque ?? opaquePipeline,
            skinnedPipeline: skinnedOpaquePipeline,
            morphedSkinnedPipeline: morphedSkinnedOpaquePipeline,
            state: &state
        )
        endMaterialDrawState(state: &state)
        encodeTerrain(items: scene.terrain, state: &state)
        state.cullList = .alphaTested
        state.materialDepth = .writes
        encode(
            groups: frameDrawGroups.alphaTested,
            staticPipeline: rayTraced?.alphaTest ?? alphaTestPipeline,
            skinnedPipeline: skinnedAlphaTestPipeline,
            morphedSkinnedPipeline: morphedSkinnedAlphaTestPipeline,
            skippingBlended: true,
            state: &state
        )
        state.cullList = nil
        endMaterialDrawState(state: &state)
    }

    public func encodeScenePass(
        descriptor target: MTL4RenderPassDescriptor,
        slot: Int,
        projection: float4x4,
        interpolatedTarget: MTL4RenderPassDescriptor? = nil
    ) -> Bool {
        let view = frameInput.view.viewMatrix()
        // Upscaling renders the scene smaller with a jittered projection. Culling keeps
        // the unjittered frustum, so both paths cull the same instances.
        let upscaleFrame = beginUpscaleFrame(
            target: target, interpolatedTarget: interpolatedTarget, projection: projection,
            view: view
        )
        let frustum = Frustum(viewProjection: projection * view)
        planSceneDepthCopy(projection: projection)
        let frameOffset = updateFrameUniforms(
            slot: slot,
            viewProjection: upscaleFrame?.jitteredViewProjection ?? projection * view
        )
        target.colorAttachments[0].clearColor = sceneBackground
        let sceneTarget = upscaleFrame.map { upscaleSceneDescriptor($0, matching: target) }
            ?? target
        let grade = imageSpaceGrade(descriptor: sceneTarget, slot: slot)
        refraction.splits = refractionSplits()
        guard
            let descriptor = scenePassDescriptor(
                sceneTarget, grade: grade, storesDepth: waterDepth.copies || refraction.splits
            ),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return false }
        bindScenePassFrameArguments(encoder: encoder, frameOffset: frameOffset)
        var state = ScenePassState(encoder: encoder, slot: slot, frustum: frustum)
        guard
            encodeSceneLayers(descriptor: descriptor, frameOffset: frameOffset, state: &state)
        else { return false }
        if let grade {
            guard
                encodeImageSpaceGrade(
                    grade, descriptor: descriptor, state: &state, frameOffset: frameOffset
                )
            else { return false }
        }
        // World-space diagnostics remain depth-tested and sit below every
        // screen-space layer.
        encodeWorldOverlay(state: &state)
        if let upscaleFrame {
            guard
                let sceneDepth = descriptor.depthAttachment.texture,
                let upscaled = encodeUpscale(
                    upscaleFrame, sceneDepth: sceneDepth, target: target, state: state,
                    frameOffset: frameOffset
                )
            else { return false }
            state = upscaled
        }
        // SWF layer before the dev UI overlay so stats/readouts stay on top. Both draw
        // at the frame size, also when the scene was upscaled.
        encodeScreenBlood(descriptor: target, state: &state)
        encodeSWF(descriptor: target, state: &state)
        encodeMovie(descriptor: target, state: &state)
        encodeUI(descriptor: target, state: &state)
        lastDrawStats = state.stats
        state.encoder.endEncoding()
        return true
    }

    /// Sky, world geometry, effects, and the first-person arms. False when the depth
    /// split cannot open its encoder.
    private func encodeSceneLayers(
        descriptor: MTL4RenderPassDescriptor,
        frameOffset: Int,
        state: inout ScenePassState
    ) -> Bool {
        let encoder = state.encoder
        if scene.sky != nil, effectiveRenderLayers.contains(.sky) {
            encoder.setRenderPipelineState(skyPipeline)
            encoder.setCullMode(.none)
            encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
            encodeClouds(state: &state)
        }
        encoder.setDepthStencilState(depthState)
        // Wireframe is a raster state rather than a channel, so it is set on the
        // encoder here and reset before the screen-space layers, which share this
        // encoder and would otherwise wireframe the HUD.
        state.fillMode = renderDebug.mode == .wireframe ? .lines : .fill
        encoder.setTriangleFillMode(state.fillMode)
        encodeSceneGeometry(state: &state)
        encodeMembranes(state: &state)
        encodeDecals(state: &state)
        encodeGrass(groups: scene.grass, state: &state)
        // The depth split replaces the encoder, so later layers use `state.encoder`.
        guard copySceneDepth(descriptor: descriptor, frameOffset: frameOffset, state: &state)
        else { return false }
        encodeWater(items: scene.water, state: &state)
        encodeBlendedGroups(state: &state)
        encodeWeaponBlood(state: &state)
        guard
            encodeRefraction(descriptor: descriptor, frameOffset: frameOffset, state: &state)
        else { return false }
        encodeParticles(
            items: sortedParticles(visibleParticles(activeParticles, frustum: state.frustum)),
            enabled: particlesEnabled,
            sorted: particleSortingEnabled,
            layer: activeParticleLayer,
            state: &state
        )
        encodeParticles(
            items: precipitation.drawItems,
            enabled: precipitationEnabled,
            state: &state
        )
        encodeMenuScene(descriptor: descriptor, state: &state)
        encodeFirstPersonArms(descriptor: descriptor, state: &state)
        state.encoder.setTriangleFillMode(.fill)
        return true
    }
}
