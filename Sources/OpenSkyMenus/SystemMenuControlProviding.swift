// Main-app system menu seam. Keeps the verification panel independent
// of GameViewController while exposing the live menu-stack state, the two
// settings placeholders the milestone surfaces (data root, audio volume), and
// the vanilla-movie presentation state behind them.

import Foundation
import OpenSkyRendering

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

    /// Read-only here: Settings (Cmd+,) owns changing the data root.
    public let dataRootPath: String?
    public let dataRootSource: String?
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
    public let page: SystemMenuPageSnapshot

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
        audioEnabled: Bool,
        movieEnabled: Bool,
        movieLoaded: Bool,
        movieError: String?,
        movieDrawStats: SWFDrawStats,
        movieFaults: Int,
        movieMissingNames: Int,
        movieEntryTitles: [String],
        movieState: String?,
        page: SystemMenuPageSnapshot
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
        self.audioEnabled = audioEnabled
        self.movieEnabled = movieEnabled
        self.movieLoaded = movieLoaded
        self.movieError = movieError
        self.movieDrawStats = movieDrawStats
        self.movieFaults = movieFaults
        self.movieMissingNames = movieMissingNames
        self.movieEntryTitles = movieEntryTitles
        self.movieState = movieState
        self.page = page
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
    /// Asks before deleting the save selected on the Save or Load page.
    func deleteSelectedSave()
    var systemMenuSnapshot: SystemMenuControlSnapshot { get }
    func refocusGameView()
}
