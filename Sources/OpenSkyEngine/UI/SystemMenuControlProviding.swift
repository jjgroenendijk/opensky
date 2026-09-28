// Main-app system menu seam (M8.5.1). Keeps the verification panel independent
// of GameViewController while exposing the live menu-stack state, the two
// settings placeholders the milestone surfaces (data root, audio volume), and
// the vanilla-movie presentation state behind them.

import Foundation

nonisolated public struct SystemMenuControlSnapshot: Equatable, Sendable {
    public let isOpen: Bool
    public let entryTitles: [String]
    public let selectedIndex: Int
    public let lastOutcome: String?
    public let settingsRevealed: Bool
    /// Menu-stack identifiers currently open, top last. Proves the menu drives
    /// the engine's own stack rather than a private flag.
    public let openMenus: [String]
    public let worldSimPaused: Bool

    /// Settings placeholders. Read-only for the data root (Settings owns
    /// changing it, Cmd+,); the volume is live and writes through the same
    /// audio seam as World > Audio.
    public let dataRootPath: String?
    public let dataRootSource: String?
    public let masterVolume: Float
    public let audioEnabled: Bool

    /// Vanilla presentation layer.
    public let movieEnabled: Bool
    public let movieLoaded: Bool
    public let movieError: String?
    public let movieDrawStats: SWFDrawStats
    public let movieFaults: Int
    public let movieMissingNames: Int
    /// Row labels the vanilla movie's `SystemPage` built for itself.
    public let movieEntryTitles: [String]
    /// The movie page driven to the front (`System`).
    public let movieState: String?

    public init(
        isOpen: Bool,
        entryTitles: [String],
        selectedIndex: Int,
        lastOutcome: String?,
        settingsRevealed: Bool,
        openMenus: [String],
        worldSimPaused: Bool,
        dataRootPath: String?,
        dataRootSource: String?,
        masterVolume: Float,
        audioEnabled: Bool,
        movieEnabled: Bool,
        movieLoaded: Bool,
        movieError: String?,
        movieDrawStats: SWFDrawStats,
        movieFaults: Int,
        movieMissingNames: Int,
        movieEntryTitles: [String],
        movieState: String?
    ) {
        self.isOpen = isOpen
        self.entryTitles = entryTitles
        self.selectedIndex = selectedIndex
        self.lastOutcome = lastOutcome
        self.settingsRevealed = settingsRevealed
        self.openMenus = openMenus
        self.worldSimPaused = worldSimPaused
        self.dataRootPath = dataRootPath
        self.dataRootSource = dataRootSource
        self.masterVolume = masterVolume
        self.audioEnabled = audioEnabled
        self.movieEnabled = movieEnabled
        self.movieLoaded = movieLoaded
        self.movieError = movieError
        self.movieDrawStats = movieDrawStats
        self.movieFaults = movieFaults
        self.movieMissingNames = movieMissingNames
        self.movieEntryTitles = movieEntryTitles
        self.movieState = movieState
    }
}

@MainActor
public protocol SystemMenuControlProviding: AnyObject {
    var systemMenuIsOpen: Bool { get }
    /// Drives the vanilla `Interface\quest_journal.swf` presentation layer. Off
    /// keeps the engine-side selector working with the gameplay HUD on screen.
    var systemMenuMovieEnabled: Bool { get set }
    var systemMenuMasterVolume: Float { get set }
    func openSystemMenu()
    func closeSystemMenu()
    /// Routes one menu event through the same path as keyboard input, so the
    /// panel buttons and the live keys cannot diverge.
    func sendSystemMenuInput(_ event: MenuInputEvent)
    var systemMenuSnapshot: SystemMenuControlSnapshot { get }
    func refocusGameView()
}
