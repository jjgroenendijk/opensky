// The GPU features the player settings ask for. The launcher's Graphics page and the
// the rendering performance readout write the same settings.

import Metal
import OpenSkyCells
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRendering

extension RenderScale {
    public init(store: PlayerSettingsStore) {
        self.init(settingIndex: Int(store.value(.renderScale)))
    }
}

extension UpscalerKind {
    public init(store: PlayerSettingsStore) {
        self.init(settingIndex: Int(store.value(.upscaler)))
    }
}

extension PostEffectSettings {
    public init(store: PlayerSettingsStore) {
        self.init()
        ambientOcclusion = store.bool(.ambientOcclusion)
        volumetricLight = store.bool(.volumetricLight)
        depthOfField = store.bool(.depthOfField)
        lensFlare = store.bool(.lensFlare)
        fxaa = store.bool(.fxaa)
        let quality = store.value(.volumetricQuality)
        volumetricQuality = quality.isFinite ? Int(min(max(quality, 0), 2)) : 1
    }
}

extension GameSession {
    /// The renderer's GPU features, and the tone mapping the frame input carries.
    public func applyGraphicsSettings(_ store: PlayerSettingsStore) {
        renderer.applyGraphicsSettings(store)
        imageSpace.toneMapping.enabled = store.bool(.toneMapping)
    }
}

extension Renderer {
    public func applyGraphicsSettings(_ store: PlayerSettingsStore) {
        gpuCullingEnabled = store.bool(.gpuCulling)
        roomCullingEnabled = store.bool(.roomCulling)
        textureStreaming.enabled = store.bool(.textureStreaming)
        textureStreaming.budgetBytes = Self.textureBudgetBytes(store: store, device: device)
        rayTracedShadows.enabled = store.bool(.rayTracedShadows)
        let upscale = RenderScale.resolve(
            RenderScale(store: store), upscaler: UpscalerKind(store: store),
            temporalAntiAliasing: store.bool(.temporalAntiAliasing)
        )
        renderScale = upscale.scale
        upscaler = upscale.upscaler
        frameInterpolationEnabled = store.bool(.frameInterpolation)
        meshShaderGrassEnabled = store.bool(.meshShaderGrass)
        waterDepth.enabled = store.bool(.waterDepth)
        waterDepth.screenSpaceReflections = store.bool(.screenSpaceReflections)
        terrainNormalMapsEnabled = store.bool(.terrainNormalMaps)
        shadingTerms = SurfaceShadingSetting.terms(store: store)
        lightAnimationEnabled = store.bool(.lightAnimation)
        particleSortingEnabled = store.bool(.particleSorting)
        referenceFades = ReferenceFadeDistances(
            actors: store.value(.fadeActors), items: store.value(.fadeItems),
            objects: store.value(.fadeObjects)
        )
        precipitationOcclusionEnabled = store.bool(.precipitationOcclusion)
        postEffects = PostEffectSettings(store: store)
        surfaceFeatures.imageBasedLighting = store.bool(.imageBasedLighting)
        surfaceFeatures.improvedSnow = store.bool(.improvedSnow)
        surfaceFeatures.projectedTextures = store.bool(.projectedTextures)
        let focus = store.value(.focusShadows)
        focusShadowCount = focus.isFinite ? Int(min(max(focus, 0), 4)) : 0
        meshLODDistances = MeshLODDistances(
            level1: store.value(.meshLODLevel1), level2: store.value(.meshLODLevel2)
        )
        if let grass = GrassRenderPolicy.drawDistance(fadeStart: store.value(.grassFadeStart)) {
            grassDrawDistance = grass
        }
        shadowSettings = ShadowSettings(
            distance: store.value(.shadowDistance), resolution: store.value(.shadowMapResolution)
        )
        let caps = PlayerSettingsCatalog.frameRateCapOptions
        frameRateCap = caps[min(max(Int(store.value(.frameRateCap)), 0), caps.count - 1)]
    }

    /// Automatic reads the device now, so it counts what is already allocated.
    public static func textureBudgetBytes(
        store: PlayerSettingsStore,
        device: (any MTLDevice)? = nil
    ) -> Int {
        let device = device ?? MTLCreateSystemDefaultDevice()
        return TextureBudget.bytes(
            choice: Int(store.value(.textureBudget)),
            workingSetBytes: device?.recommendedMaxWorkingSetSize ?? 0,
            allocatedBytes: UInt64(device?.currentAllocatedSize ?? 0)
        )
    }

    /// Streams the textures of the cells `runner` builds from now on.
    public func attachTextureStreaming(to runner: any CellBuildRunning) {
        guard let runner = runner as? SerialCellBuildRunner else { return }
        runner.attachTextureStreaming(textureStreaming.mailbox)
        textureStreaming.reader = runner
    }
}
