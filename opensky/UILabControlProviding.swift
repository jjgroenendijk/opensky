// Narrow live-renderer seam consumed by World > UI Lab controls (M8.1.1). The
// panel drives the screen-space UI layer (enable, sample scene, scale) and
// reads its per-frame draw accounting only through this bridge, never renderer
// internals. `refocusGameView` overlaps ShadowControlProviding on purpose so
// one game-view implementation satisfies both surfaces.

/// UI Lab readout: overlay state plus the last-frame UIDrawStats mirror.
nonisolated struct UILabControlSnapshot: Equatable {
    let overlayEnabled: Bool
    let sampleShown: Bool
    let scale: Float
    let stats: UIDrawStats
}

@MainActor
protocol UILabControlProviding: AnyObject {
    var uiOverlayEnabled: Bool { get set }
    var uiSampleShown: Bool { get set }
    var uiScale: Float { get set }
    var uiSnapshot: UILabControlSnapshot { get }
    func refocusGameView()
}
