// Renderer-source bridge for issue #422. It is deliberately a CellStreamer
// satellite: residency and the latest path already live here, while the
// renderer only owns the generic source registry and toggles.

extension CellStreamer {
    func appendNavigationWorldOverlay(
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
