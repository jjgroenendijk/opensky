// Narrow live-renderer seam consumed by World > UI Lab controls (M8.1.1,
// extended M8.1.4). The panel drives the screen-space UI layer (enable, sample
// scenes, scale), previews menu mode (push/pop/clear against the real
// MenuModeController), and reads localized-strings state — only through this
// bridge, never renderer or controller internals. `refocusGameView` overlaps
// ShadowControlProviding on purpose so one game-view implementation satisfies
// both surfaces.

/// UI Lab readout: overlay state plus the last-frame UIDrawStats mirror.
nonisolated struct UILabControlSnapshot: Equatable {
    let overlayEnabled: Bool
    let sampleShown: Bool
    let scale: Float
    let stats: UIDrawStats
}

/// Menu-mode readout for the UI Lab preview (M8.1.4): the live
/// MenuModeController state the panel mirrors at 2 Hz.
nonisolated struct MenuModeControlSnapshot: Equatable {
    let isMenuMode: Bool
    let topMenuName: String?
    let stackDepth: Int
    let isWorldSimPaused: Bool
}

/// Localized-strings readout (M8.1.4): synthetic sample state plus the merged
/// provider counts over the located install (zero files on vanilla — the
/// mechanism is used by mods and localized builds).
nonisolated struct LocalizedLabelsControlSnapshot: Equatable {
    let sampleShown: Bool
    let sampleKeyCount: Int
    let language: String
    let installLoaded: Bool
    let installFileCount: Int
    let installKeyCount: Int
}

@MainActor
protocol UILabControlProviding: AnyObject {
    var uiOverlayEnabled: Bool { get set }
    var uiSampleShown: Bool { get set }
    var uiScale: Float { get set }
    var uiSnapshot: UILabControlSnapshot { get }
    func refocusGameView()

    // Menu-mode preview (M8.1.4): drives the real MenuModeController.
    func pushPreviewMenu()
    func popPreviewMenu()
    func clearPreviewMenus()
    var menuModeSnapshot: MenuModeControlSnapshot { get }

    // Localized-strings preview (M8.1.4).
    var uiLocalizedSampleShown: Bool { get set }
    var localizedLabelsSnapshot: LocalizedLabelsControlSnapshot { get }
}
