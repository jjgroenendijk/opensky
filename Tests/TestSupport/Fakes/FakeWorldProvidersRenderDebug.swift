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

    func clearPipelineCache() -> Int {
        pipelineCacheClears += 1
        return 1
    }
}
