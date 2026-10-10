// The GPU features the player settings ask for. The launcher's Graphics page and the
// Rendering Performance panel write the same settings.

import Metal
import OpenSkyGameData
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

extension Renderer {
    public func applyGraphicsSettings(_ store: PlayerSettingsStore) {
        gpuCullingEnabled = store.bool(.gpuCulling)
        textureStreaming.enabled = store.bool(.textureStreaming)
        textureStreaming.budgetBytes = Self.textureBudgetBytes(store: store, device: device)
        rayTracedShadows.enabled = store.bool(.rayTracedShadows)
        renderScale = RenderScale(store: store)
        upscaler = UpscalerKind(store: store)
        frameInterpolationEnabled = store.bool(.frameInterpolation)
        meshShaderGrassEnabled = store.bool(.meshShaderGrass)
        waterDepth.enabled = store.bool(.waterDepth)
        terrainNormalMapsEnabled = store.bool(.terrainNormalMaps)
        imageSpace.toneMapping.enabled = store.bool(.toneMapping)
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
