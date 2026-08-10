// Render-debug bridge over the live renderer (issue #144), consumed only by
// `World > Render Debug` through `RenderDebugControlProviding`.

extension GameViewController: RenderDebugControlProviding {
    var renderDebugMode: RenderDebugMode {
        get { renderer?.renderDebug.mode ?? .off }
        set { renderer?.renderDebug.mode = newValue }
    }

    var renderDebugLayers: RenderLayer {
        get { renderer?.renderDebug.layers ?? .all }
        set { renderer?.renderDebug.layers = newValue }
    }

    var renderDebugSnapshot: RenderDebugControlSnapshot {
        RenderDebugControlSnapshot(
            mode: renderDebugMode,
            layers: renderDebugLayers,
            effectiveLayers: renderer?.effectiveRenderLayers ?? .all,
            stats: renderer?.lastDrawStats ?? SceneDrawStats(),
            shadowStats: renderer?.lastShadowDrawStats ?? ShadowDrawStats()
        )
    }
}
