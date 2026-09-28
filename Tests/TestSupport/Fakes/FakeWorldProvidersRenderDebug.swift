// The shared provider fake's render-debug half (issue #144). Split from
// `FakeWorldProviders.swift` for the same reason its AI half is: that file is
// at the strict-lint size cap, and only its stored state has to live there.

@testable import opensky

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
}
