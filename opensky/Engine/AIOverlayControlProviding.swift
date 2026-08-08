// Narrow provider seam for the M16 acceptance panel. Issue #422 supplies the
// renderer toggles and readout; issue #203 adds the actual controls without
// exposing Renderer or CellStreamer to the shell.

nonisolated struct AIOverlayControlSnapshot: Equatable {
    let navmeshOverlayEnabled: Bool
    let pathOverlayEnabled: Bool
    let stats: WorldOverlayDrawStats
}

@MainActor
protocol AIOverlayControlProviding: AnyObject {
    var navmeshOverlayEnabled: Bool { get set }
    var pathOverlayEnabled: Bool { get set }
    var aiOverlaySnapshot: AIOverlayControlSnapshot { get }
}
