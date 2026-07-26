// Main-app system menu seam (M8.5.1). Keeps the verification panel independent
// of GameViewController while exposing the live menu-stack state, the two
// settings placeholders the milestone surfaces (data root, audio volume), and
// the vanilla-movie presentation state behind them.

import Foundation

nonisolated struct SystemMenuControlSnapshot: Equatable {
    let isOpen: Bool
    let entryTitles: [String]
    let selectedIndex: Int
    let lastOutcome: String?
    let settingsRevealed: Bool
    /// Menu-stack identifiers currently open, top last. Proves the menu drives
    /// the engine's own stack rather than a private flag.
    let openMenus: [String]
    let worldSimPaused: Bool

    /// Settings placeholders. Read-only for the data root (Settings owns
    /// changing it, Cmd+,); the volume is live and writes through the same
    /// audio seam as World > Audio.
    let dataRootPath: String?
    let dataRootSource: String?
    let masterVolume: Float
    let audioEnabled: Bool

    /// Vanilla presentation layer.
    let movieEnabled: Bool
    let movieLoaded: Bool
    let movieError: String?
    let movieDrawStats: SWFDrawStats
    let movieFaults: Int
    let movieMissingNames: Int
    /// Row labels the vanilla movie built for itself. These are the title
    /// screen's rows, not the engine selector's — the two menus are different
    /// menus, and the readout shows both so that stays visible.
    let movieEntryTitles: [String]
    /// The movie's own state name (`Main`, `PressStart`, …).
    let movieState: String?
}

@MainActor
protocol SystemMenuControlProviding: AnyObject {
    var systemMenuIsOpen: Bool { get }
    /// Drives the vanilla `Interface\startmenu.swf` presentation layer. Off
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
