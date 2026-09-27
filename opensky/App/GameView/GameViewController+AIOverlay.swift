// M16 world-overlay bridge over the live renderer. The gate panel arrives in
// issue #203 and consumes only AIOverlayControlProviding.

extension GameViewController: AIOverlayControlProviding {
    var navmeshOverlayEnabled: Bool {
        get { renderer?.navmeshOverlayEnabled ?? false }
        set { renderer?.navmeshOverlayEnabled = newValue }
    }

    var pathOverlayEnabled: Bool {
        get { renderer?.pathOverlayEnabled ?? false }
        set { renderer?.pathOverlayEnabled = newValue }
    }

    var detectionOverlayEnabled: Bool {
        get { renderer?.detectionOverlayEnabled ?? false }
        set { renderer?.detectionOverlayEnabled = newValue }
    }

    var aiOverlaySnapshot: AIOverlayControlSnapshot {
        AIOverlayControlSnapshot(
            navmeshOverlayEnabled: navmeshOverlayEnabled,
            pathOverlayEnabled: pathOverlayEnabled,
            detectionOverlayEnabled: detectionOverlayEnabled,
            stats: renderer?.lastWorldOverlayDrawStats ?? WorldOverlayDrawStats()
        )
    }
}

extension GameViewController {
    func wireAIOverlay(renderer: Renderer, streamer: CellStreamer) {
        renderer.worldOverlaySources
            .register(identifier: "navigation") { [weak streamer] context, list in
                streamer?.appendNavigationWorldOverlay(context: context, to: &list)
            }
    }
}
