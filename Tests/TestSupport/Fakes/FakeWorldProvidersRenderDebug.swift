// The render-debug and render-performance part of the shared provider fake, split from
// `FakeWorldProviders.swift`, which keeps only the stored state.

@testable import OpenSkyRendering

extension FakeWorldProviders {
    var renderDebugMode: RenderDebugMode {
        get { renderDebug.mode }
        set { renderDebug.mode = newValue }
    }

    var renderDebugLayers: RenderLayer {
        get { renderDebug.layers }
        set { renderDebug.layers = newValue }
    }

    /// The fake folds the mask through the same policy the renderer does, so a
    /// panel test sees the composition rule rather than a second answer.
    var renderDebugSnapshot: RenderDebugControlSnapshot {
        RenderDebugControlSnapshot(
            mode: renderDebug.mode,
            layers: renderDebug.layers,
            effectiveLayers: RenderLayerPolicy.effective(
                mask: renderDebug.layers,
                grassEnabled: grassEnabled,
                particlesEnabled: particlesEnabled,
                precipitationEnabled: precipitationEnabled
            ),
            stats: renderDebugStats,
            shadowStats: shadowDrawStats
        )
    }

    var renderPerformanceSnapshot: RenderPerformanceSnapshot? {
        get { renderPerformance.snapshot }
        set { renderPerformance.snapshot = newValue }
    }

    var pipelineCacheEnabled: Bool {
        get { renderPerformance.pipelineCacheEnabled }
        set { renderPerformance.pipelineCacheEnabled = newValue }
    }

    var gpuCullingEnabled: Bool {
        get { renderPerformance.gpuCullingEnabled }
        set { renderPerformance.gpuCullingEnabled = newValue }
    }

    var textureStreamingEnabled: Bool {
        get { renderPerformance.textureStreamingEnabled }
        set { renderPerformance.textureStreamingEnabled = newValue }
    }

    var textureBudgetIndex: Int {
        get { renderPerformance.textureBudgetIndex }
        set { renderPerformance.textureBudgetIndex = newValue }
    }

    var rayTracedShadowsEnabled: Bool {
        get { renderPerformance.rayTracedShadowsEnabled }
        set { renderPerformance.rayTracedShadowsEnabled = newValue }
    }

    var rayTracedShadowView: Bool {
        get { renderPerformance.rayTracedShadowView }
        set { renderPerformance.rayTracedShadowView = newValue }
    }

    var renderScale: RenderScale {
        get { renderPerformance.renderScale }
        set { renderPerformance.renderScale = newValue }
    }

    var upscaler: UpscalerKind {
        get { renderPerformance.upscaler }
        set { renderPerformance.upscaler = newValue }
    }

    var frameInterpolationEnabled: Bool {
        get { renderPerformance.frameInterpolationEnabled }
        set { renderPerformance.frameInterpolationEnabled = newValue }
    }

    var meshShaderGrassEnabled: Bool {
        get { renderPerformance.meshShaderGrassEnabled }
        set { renderPerformance.meshShaderGrassEnabled = newValue }
    }

    var pipelineCacheClears: Int {
        renderPerformance.pipelineCacheClears
    }

    func clearPipelineCache() -> Int {
        renderPerformance.pipelineCacheClears += 1
        return 1
    }
}

/// The `RenderPerformanceControlProviding` state of the fake.
struct FakeRenderPerformanceState {
    var snapshot: RenderPerformanceSnapshot? = RenderPerformanceSnapshot()
    var pipelineCacheEnabled = true
    var gpuCullingEnabled = true
    var textureStreamingEnabled = true
    var textureBudgetIndex = 2
    var rayTracedShadowsEnabled = false
    var rayTracedShadowView = false
    var renderScale = RenderScale.off
    var upscaler = UpscalerKind.temporal
    var frameInterpolationEnabled = false
    var meshShaderGrassEnabled = false
    var pipelineCacheClears = 0
}
