// Live-renderer seam for Developer > UI Lab. The panel drives the screen-space
// UI layer, previews menu mode against the real `MenuModeController`, and reads
// localized-strings state only through this protocol. `refocusGameView`
// overlaps `ShadowControlProviding` so one game view satisfies both.

// UI Lab readout: overlay state plus the last-frame UIDrawStats mirror.
import OpenSkyRendering

nonisolated public struct UILabControlSnapshot: Equatable, Sendable {
    public let overlayEnabled: Bool
    public let scale: Float
    public let stats: UIDrawStats

    public init(overlayEnabled: Bool, scale: Float, stats: UIDrawStats) {
        self.overlayEnabled = overlayEnabled
        self.scale = scale
        self.stats = stats
    }
}

/// Menu-mode readout for the UI Lab preview: the live
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

/// Localized-strings readout: synthetic sample state plus the merged
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

    // Menu-mode preview: drives the real MenuModeController.
    func pushPreviewMenu()
    func popPreviewMenu()
    func clearPreviewMenus()
    var menuModeSnapshot: MenuModeControlSnapshot { get }

    // Localized-strings preview.
    var uiLocalizedSampleShown: Bool { get set }
    var localizedLabelsSnapshot: LocalizedLabelsControlSnapshot { get }
}
