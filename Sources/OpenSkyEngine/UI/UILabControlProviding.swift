// Narrow live-renderer seam consumed by Developer > UI Lab controls (M8.1.1,
// extended M8.1.4). The panel drives the screen-space UI layer (enable, sample
// scenes, scale), previews menu mode (push/pop/clear against the real
// MenuModeController), and reads localized-strings state — only through this
// bridge, never renderer or controller internals. `refocusGameView` overlaps
// ShadowControlProviding on purpose so one game-view implementation satisfies
// both surfaces.

/// UI Lab readout: overlay state plus the last-frame UIDrawStats mirror.
nonisolated public struct UILabControlSnapshot: Equatable, Sendable {
    public let overlayEnabled: Bool
    public let sampleShown: Bool
    public let scale: Float
    public let stats: UIDrawStats

    public init(overlayEnabled: Bool, sampleShown: Bool, scale: Float, stats: UIDrawStats) {
        self.overlayEnabled = overlayEnabled
        self.sampleShown = sampleShown
        self.scale = scale
        self.stats = stats
    }
}

/// Menu-mode readout for the UI Lab preview (M8.1.4): the live
/// MenuModeController state the panel mirrors at 2 Hz.
nonisolated public struct MenuModeControlSnapshot: Equatable, Sendable {
    public let isMenuMode: Bool
    public let topMenuName: String?
    public let stackDepth: Int
    public let isWorldSimPaused: Bool

    public init(isMenuMode: Bool, topMenuName: String?, stackDepth: Int, isWorldSimPaused: Bool) {
        self.isMenuMode = isMenuMode
        self.topMenuName = topMenuName
        self.stackDepth = stackDepth
        self.isWorldSimPaused = isWorldSimPaused
    }
}

/// Localized-strings readout (M8.1.4): synthetic sample state plus the merged
/// provider counts over the located install (zero files on vanilla — the
/// mechanism is used by mods and localized builds).
nonisolated public struct LocalizedLabelsControlSnapshot: Equatable, Sendable {
    public let sampleShown: Bool
    public let sampleKeyCount: Int
    public let language: String
    public let installLoaded: Bool
    public let installFileCount: Int
    public let installKeyCount: Int

    public init(
        sampleShown: Bool,
        sampleKeyCount: Int,
        language: String,
        installLoaded: Bool,
        installFileCount: Int,
        installKeyCount: Int
    ) {
        self.sampleShown = sampleShown
        self.sampleKeyCount = sampleKeyCount
        self.language = language
        self.installLoaded = installLoaded
        self.installFileCount = installFileCount
        self.installKeyCount = installKeyCount
    }
}

@MainActor
public protocol UILabControlProviding: AnyObject {
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
