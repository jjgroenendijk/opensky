import Metal
import MetalKit
import OpenSkyFormatsCore
import OpenSkyFormatsESM
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
    }

    /// Writes this frame's uniforms into its 256-byte-aligned slot and
    /// returns the byte offset of that slot. `viewProjection` is computed by
    /// the caller (encodeScenePass shares it with the frustum). Sun/ambient
    /// come from the injected SceneCamera.
    private func updateFrameUniforms(slot: Int, viewProjection: float4x4) -> Int {
        let offset = Self.alignedFrameUniformsSize * slot
        let interiorLighting = scene.lighting
        // Weather is an exterior-only source: interiors keep their own baked
        // CELL/LGTM lighting untouched (weatherLight nil there). The sky
        // palette applies only when the scene actually draws a sky.
        let weatherLight = interiorLighting == nil ? currentResolvedWeather : nil
        let weatherSky = scene.sky != nil ? weatherLight : nil
        let ambient = weatherLight?.directionalAmbient
            ?? interiorLighting?.directionalAmbient ?? .black
        let fog = Self.resolvedFog(weatherLight: weatherLight, interior: interiorLighting?.fog)
        let grassDistance = simd_clamp(
            grassDrawDistance,
            GrassRenderPolicy.minimumDrawDistance,
            GrassRenderPolicy.maximumDrawDistance
        )
        var uniforms = FrameUniforms(
            viewProjectionMatrix: viewProjection,
            cameraPosition: freeFlyCamera.position,
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
            timeOfDayHours: timeOfDay,
            animationTime: animationTime,
            shadowViewProjections: (
                shadowCascadeMatrix(0), shadowCascadeMatrix(1), shadowCascadeMatrix(2)
            ),
            shadowCascadeSplits: shadowCascadeSplitBounds(),
            cameraForward: freeFlyCamera.forward,
            shadowsEnabled: shadowsActiveThisFrame ? 1 : 0,
            shadowInverseResolution: 1 / Float(ShadowConstant.mapResolution.rawValue),
            shadowSampleRadius: shadowSampleRadius,
            weatherSkyEnabled: weatherSky == nil ? 0 : 1,
            weatherSkyUpperColor: weatherSky?.skyUpper ?? .zero,
            weatherSkyLowerColor: weatherSky?.skyLower ?? .zero,
            weatherHorizonColor: weatherSky?.horizon ?? .zero,
            weatherSunColor: weatherSky?.sun ?? .zero,
            weatherGlareColor: weatherSky?.sunGlare ?? .zero,

            cameraRight: freeFlyCamera.right,
            cameraUp: simd_normalize(simd_cross(freeFlyCamera.right, freeFlyCamera.forward)),
            grassWind: currentWind.direction * currentWind.speed
                * simd_clamp(grassWindScale, 0, GrassRenderPolicy.maximumWindScale),
            grassFadeDistances: SIMD2(
                max(grassDistance * 0.7, GrassRenderPolicy.minimumDrawDistance * 0.5),
                grassDistance
            ),
            debugMode: renderDebug.mode.rawValue
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
        pointLightCount: Int
    ) -> Int {
        let offset = Self.alignedDrawUniformsSize * (slot * drawUniformSlotCapacity + draw)
        let material = group.material
        let effect = material.effect
        var uniforms = DrawUniforms(
            uvOffset: material.uvOffset,
            uvScale: material.uvScale,
            materialAlpha: material.alpha,
            alphaThreshold: material.alphaTestThreshold ?? 0,
            pointLightCount: UInt32(pointLightCount),
            receivesShadows: group.receivesShadows ? 1 : 0,
            layerCategory: group.layer.rawValue,
            effectFlags: effect?.flags ?? 0,
            effectBaseColor: effect?.baseColor ?? .zero,
            effectFalloff: effect?.falloff ?? .zero,
            effectBaseColorScale: effect?.baseColorScale ?? 1
        )
        drawUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<DrawUniforms>.size)
        return offset
    }

    /// Selects + writes nearest supported point lights for one draw. Returns
    /// count plus byte offset bound at BufferIndexPointLights.
    private func writePointLights(
        near position: SIMD3<Float>,
        slot: Int,
        draw: Int
    ) -> (count: Int, byteOffset: Int) {
        let limit = LightingConstant.maxPointLights.rawValue
        let pick = pointLightPick(near: position, limit: limit)
        let stride = MemoryLayout<PointLightUniform>.stride
        let first = (slot * drawUniformSlotCapacity + draw) * limit
        for index in 0 ..< pick.count {
            let light = scene.pointLights[Int(pick.indices[index])]
            let live = light.animated(at: animationTime, enabled: lightAnimationEnabled)
            var uniform = PointLightUniform(
                positionRadius: SIMD4(live.position, light.radius),
                colorFalloff: SIMD4(live.color, light.falloffExponent)
            )
            pointLightBuffer.contents().advanced(by: (first + index) * stride)
                .copyMemory(from: &uniform, byteCount: MemoryLayout<PointLightUniform>.size)
        }
        return (pick.count, first * stride)
    }

    /// Group and terrain centers repeat every frame, so their picks are kept per scene.
    /// Moving centers, such as the player body, would grow the cache, so it has a cap.
    private func pointLightPick(near position: SIMD3<Float>, limit: Int) -> PointLightPick {
        if let cached = pointLightPicks[position] {
            return cached
        }
        if pointLightPicks.count >= Self.pointLightPickCacheLimit {
            pointLightPicks.removeAll(keepingCapacity: true)
        }
        let pick = scene.nearestPointLightPick(to: position, limit: limit)
        pointLightPicks[position] = pick
        return pick
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
                instanceColor: SIMD4(1, 1, 1, 1),
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

    /// Terrain variant of updateDrawUniforms: same ring, same aligned slots
    /// (slot size covers both structs), TerrainDrawUniforms layout.
    private func updateTerrainDrawUniforms(
        slot: Int,
        draw: Int,
        item: TerrainDrawItem,
        pointLightCount: Int
    ) -> Int {
        let offset = Self.alignedDrawUniformsSize * (slot * drawUniformSlotCapacity + draw)
        var uniforms = TerrainDrawUniforms(
            modelMatrix: item.modelMatrix,
            normalMatrix: item.normalMatrix,
            uvOffset: item.material.uvOffset,
            uvScale: item.material.uvScale,
            layerCount: UInt32(min(item.layerTextures.count, TerrainConstant.maxLayers.rawValue)),
            pointLightCount: UInt32(pointLightCount),
            normalMapsEnabled: terrainNormalMapsEnabled ? 1 : 0
        )
        drawUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<TerrainDrawUniforms>.size)
        return offset
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
            guard !skippingBlended || !group.drawsBlended else { continue }
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
        guard let visible = visibleInstances(of: group, at: index, state: &state) else { return }
        let pipeline = pipelines.pipeline(for: group)
        if boundPipeline != ObjectIdentifier(pipeline) {
            state.encoder.setRenderPipelineState(pipeline)
            boundPipeline = ObjectIdentifier(pipeline)
        }
        // Running visible-group cursor indexes the uniform ring:
        // visible groups <= scene.drawCount <= ring capacity.
        let lightOffset = group.instances.first?.receivesPointLights == true
            ? writePointLights(near: group.lightingCenter, slot: state.slot, draw: state.drawCursor)
            : (count: 0, byteOffset: 0)
        let uniformOffset = updateDrawUniforms(
            slot: state.slot,
            draw: state.drawCursor,
            group: group,
            pointLightCount: lightOffset.count
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
        state.encoder.setCullMode(group.material.doubleSided ? .none : .back)
        state.encoder.drawInstances(of: group.mesh, visible)
    }

    /// The fragment declares the palette slot, so the diffuse fills it when a
    /// material has no palette.
    private func bindMaterialTextures(_ material: RenderMaterial) {
        let diffuse = streamedBinding(material.diffuse)
        argumentTable.setTexture(diffuse, index: TextureIndex.diffuse.rawValue)
        argumentTable.setTexture(
            material.effect?.palette?.gpuResourceID ?? diffuse,
            index: TextureIndex.effectPalette.rawValue
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

    /// Encodes the terrain splat draws: per-quadrant pipeline with the base
    /// diffuse at TextureIndexDiffuse and the ATXT layer array at
    /// TextureIndexTerrainLayer0+, and their normal maps after them. Unused layer
    /// slots rebind the base textures so every declared texture argument is valid; the shader never
    /// samples
    /// past TerrainDrawUniforms.layerCount.
    private func encodeTerrain(
        items: [TerrainDrawItem],
        state: inout ScenePassState
    ) {
        guard !items.isEmpty, effectiveRenderLayers.contains(.terrain) else { return }
        var pipelineBound = false
        for item in items {
            if let bounds = item.bounds, !state.frustum.intersects(bounds) {
                state.stats.culledInstances += 1
                continue
            }
            if !pipelineBound {
                state.encoder.setRenderPipelineState(
                    isRenderDebugActive
                        ? debugPipelines.terrain : (rayTracedPipelines?.terrain ?? terrainPipeline)
                )
                pipelineBound = true
            }
            let center = item.bounds.map { ($0.min + $0.max) * 0.5 }
                ?? SIMD3(item.modelMatrix.columns.3.x, item.modelMatrix.columns.3.y, 0)
            let lightOffset = writePointLights(
                near: center,
                slot: state.slot,
                draw: state.drawCursor
            )
            let uniformOffset = updateTerrainDrawUniforms(
                slot: state.slot,
                draw: state.drawCursor,
                item: item,
                pointLightCount: lightOffset.count
            )
            state.drawCursor += 1
            state.stats.drawCalls += 1
            state.stats.drawnInstances += 1
            argumentTable.setAddress(
                item.mesh.vertexBuffer.gpuAddress,
                index: BufferIndex.vertices.rawValue
            )
            argumentTable.setAddress(
                item.weightsBuffer.gpuAddress,
                index: BufferIndex.terrainWeights.rawValue
            )
            argumentTable.setAddress(
                drawUniformBuffer.gpuAddress + UInt64(uniformOffset),
                index: BufferIndex.drawUniforms.rawValue
            )
            argumentTable.setAddress(
                pointLightBuffer.gpuAddress + UInt64(lightOffset.byteOffset),
                index: BufferIndex.pointLights.rawValue
            )
            bindTerrainTextures(for: item)
            state.encoder.setCullMode(.back)
            state.encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: item.mesh.indexCount,
                indexType: .uint16,
                indexBuffer: item.mesh.indexBuffer.gpuAddress,
                indexBufferLength: item.mesh.indexBuffer.length
            )
        }
    }

    private func bindTerrainTextures(for item: TerrainDrawItem) {
        argumentTable.setTexture(
            streamedBinding(item.material.diffuse),
            index: TextureIndex.diffuse.rawValue
        )
        for layerSlot in 0 ..< TerrainConstant.maxLayers.rawValue {
            let texture = layerSlot < item.layerTextures.count
                ? item.layerTextures[layerSlot]
                : item.material.diffuse
            argumentTable.setTexture(
                streamedBinding(texture),
                index: TextureIndex.terrainLayer0.rawValue + layerSlot
            )
            let normal = layerSlot < item.normals.layers.count
                ? item.normals.layers[layerSlot]
                : item.normals.base
            argumentTable.setTexture(
                streamedBinding(normal),
                index: TextureIndex.terrainLayerNormal0.rawValue + layerSlot
            )
        }
        argumentTable.setTexture(
            streamedBinding(item.normals.base),
            index: TextureIndex.terrainBaseNormal.rawValue
        )
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
        let rayTraced = rayTracedPipelines
        encode(
            groups: frameDrawGroups.opaque,
            staticPipeline: rayTraced?.opaque ?? opaquePipeline,
            skinnedPipeline: skinnedOpaquePipeline,
            morphedSkinnedPipeline: morphedSkinnedOpaquePipeline,
            state: &state
        )
        encodeTerrain(items: scene.terrain, state: &state)
        state.cullList = .alphaTested
        encode(
            groups: frameDrawGroups.alphaTested,
            staticPipeline: rayTraced?.alphaTest ?? alphaTestPipeline,
            skinnedPipeline: skinnedAlphaTestPipeline,
            morphedSkinnedPipeline: morphedSkinnedAlphaTestPipeline,
            skippingBlended: true,
            state: &state
        )
        state.cullList = nil
    }

    public func encodeScenePass(
        descriptor target: MTL4RenderPassDescriptor,
        slot: Int,
        projection: float4x4,
        interpolatedTarget: MTL4RenderPassDescriptor? = nil
    ) -> Bool {
        let view = freeFlyCamera.viewMatrix()
        // Upscaling renders the scene smaller with a jittered projection. Culling keeps
        // the unjittered frustum, so both paths cull the same instances.
        let upscaleFrame = beginUpscaleFrame(
            target: target, interpolatedTarget: interpolatedTarget, projection: projection,
            view: view
        )
        let frustum = Frustum(viewProjection: projection * view)
        let frameOffset = updateFrameUniforms(
            slot: slot,
            viewProjection: upscaleFrame?.jitteredViewProjection ?? projection * view
        )
        let sceneTarget = upscaleFrame.map { upscaleSceneDescriptor($0, matching: target) }
            ?? target
        let grade = imageSpaceGrade(descriptor: sceneTarget, slot: slot)
        let waterDepth = waterReadsDepth(projection: projection)
        guard
            let descriptor = scenePassDescriptor(
                sceneTarget, grade: grade, storesDepth: waterDepth
            ),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return false }
        bindScenePassFrameArguments(encoder: encoder, frameOffset: frameOffset)
        var state = ScenePassState(encoder: encoder, slot: slot, frustum: frustum)
        guard
            encodeSceneLayers(
                descriptor: descriptor, waterDepth: waterDepth, frameOffset: frameOffset,
                state: &state
            )
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
        encodeSWF(descriptor: target, state: &state)
        encodeUI(descriptor: target, state: &state)
        lastDrawStats = state.stats
        state.encoder.endEncoding()
        return true
    }

    /// Sky, world geometry, effects, and the first-person arms. False when the water
    /// split cannot open its encoder.
    private func encodeSceneLayers(
        descriptor: MTL4RenderPassDescriptor,
        waterDepth: Bool,
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
        // The water split replaces the encoder, so later layers use `state.encoder`.
        guard
            encodeWater(
                items: scene.water, depthFrom: waterDepth ? descriptor : nil,
                frameOffset: frameOffset, state: &state
            )
        else { return false }
        encodeBlendedGroups(state: &state)
        encodeParticles(
            items: sortedParticles(scene.particles + effects.particles),
            enabled: particlesEnabled,
            sorted: particleSortingEnabled,
            state: &state
        )
        encodeParticles(
            items: precipitation.drawItems,
            enabled: precipitationEnabled,
            state: &state
        )
        encodeFirstPersonArms(descriptor: descriptor, state: &state)
        state.encoder.setTriangleFillMode(.fill)
        return true
    }
}
