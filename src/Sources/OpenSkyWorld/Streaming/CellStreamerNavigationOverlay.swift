// Navigation overlay source. Here, because residency and the latest path live in the
// streamer; the renderer owns only the source registry and toggles.

import OpenSkyNavigation
public import OpenSkyRenderCore

extension CellStreamer.NavigationSteps {
    public func appendNavigationWorldOverlay(
        context: WorldOverlayFrameContext,
        to list: inout WorldOverlayDrawList
    ) {
        guard context.navmeshOverlayEnabled || context.pathOverlayEnabled else { return }
        reconcileNavigation()
        streamer.navigationState.graph.appendWorldOverlay(
            context: context,
            path: streamer.navigationState.lastPath,
            to: &list
        )
    }
}
