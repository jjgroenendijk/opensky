// Navigation overlay source. Here, because residency and the latest path live in the
// streamer; the renderer owns only the source registry and toggles.

import OpenSkyDiagnostics

extension CellStreamer {
    public func appendNavigationWorldOverlay(
        context: WorldOverlayFrameContext,
        to list: inout WorldOverlayDrawList
    ) {
        guard context.navmeshOverlayEnabled || context.pathOverlayEnabled else { return }
        reconcileNavigation()
        navigationState.graph.appendWorldOverlay(
            context: context,
            path: navigationState.lastPath,
            to: &list
        )
    }
}
