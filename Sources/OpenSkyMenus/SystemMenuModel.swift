// Engine-owned system menu: Resume, Settings, and Quit (docs/engine/system-menu.md).
// The model owns entries, selection, and activation, so keyboard input, the
// panel, and `SystemMenuMovieBridge` share one state.

import Foundation

/// One row of the system menu. Vanilla has more rows. This enum is the only
/// place a row is named, so the movie bridge and the panel cannot disagree.
nonisolated public enum SystemMenuEntry: String, CaseIterable, Sendable {
    case resume
    case settings
    case quit

    /// Row label. Not localized yet — the vanilla string tables land with the
    /// movie-driven presentation, not with the engine-side selector.
    public var title: String {
        switch self {
        case .resume: "Resume"
        case .settings: "Settings"
        case .quit: "Quit"
        }
    }

    /// Capitalized fragment used to build accessibility identifiers, so a row's
    /// control id is derived rather than written twice.
    public var identifierFragment: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

/// What activating a row asks the host to do. `settings` has no engine effect:
/// the data-root and volume rows sit beside the menu, not in a second menu.
nonisolated public enum SystemMenuOutcome: Equatable, Sendable {
    /// Close the menu and return to gameplay.
    case resume
    /// Reveal the settings placeholders; the menu stays open.
    case showSettings
    /// Terminate the application.
    case quit

    /// Readout label for the verification panel.
    public var label: String {
        switch self {
        case .resume: "Resume"
        case .showSettings: "Settings"
        case .quit: "Quit"
        }
    }
}

/// Selection state for the system menu. A value type so the panel, the input
/// path, and the tests all reason about the same transitions without touching
/// AppKit or the renderer.
nonisolated public struct SystemMenuModel: Equatable, Sendable {
    /// Rows in display order.
    public let entries: [SystemMenuEntry]
    public private(set) var isOpen = false
    public private(set) var selectedIndex = 0
    /// The last row activated while open, for the verification readout.
    public private(set) var lastOutcome: SystemMenuOutcome?
    /// True once Settings has been activated, so the placeholders read as
    /// revealed rather than merely present.
    public private(set) var settingsRevealed = false

    public init(entries: [SystemMenuEntry] = SystemMenuEntry.allCases) {
        self.entries = entries.isEmpty ? SystemMenuEntry.allCases : entries
    }

    public var selectedEntry: SystemMenuEntry? {
        entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil
    }

    /// Opens the menu at the first row. Re-opening an already-open menu keeps
    /// the current selection so a stray open cannot silently reset it.
    public mutating func open() {
        guard !isOpen else { return }
        isOpen = true
        selectedIndex = 0
        lastOutcome = nil
        settingsRevealed = false
    }

    /// Closes the menu and clears the revealed-settings state. Selection resets
    /// so the next open starts at the top, matching the vanilla menu.
    public mutating func close() {
        isOpen = false
        selectedIndex = 0
        settingsRevealed = false
    }

    /// Moves the highlight. Vertical moves wrap, because the vanilla list wraps
    /// and a three-row menu is unusable without it; horizontal moves are
    /// accepted and ignored (a one-column list has nowhere to go) so the caller
    /// still treats the event as consumed by the menu.
    public mutating func moveSelection(_ direction: MenuInputEvent.Direction) {
        guard isOpen, !entries.isEmpty else { return }
        switch direction {
        case .up:
            selectedIndex = (selectedIndex + entries.count - 1) % entries.count
        case .down:
            selectedIndex = (selectedIndex + 1) % entries.count
        case .left, .right:
            break
        }
    }

    /// Activates the highlighted row and returns what the host must do. Resume
    /// closes the menu here; quit is left to the host because terminating is not
    /// a state transition the model can perform.
    @discardableResult
    public mutating func activateSelection() -> SystemMenuOutcome? {
        guard isOpen, let entry = selectedEntry else { return nil }
        let outcome: SystemMenuOutcome = switch entry {
        case .resume: .resume
        case .settings: .showSettings
        case .quit: .quit
        }
        lastOutcome = outcome
        switch outcome {
        case .resume:
            close()
            lastOutcome = .resume
        case .showSettings:
            settingsRevealed = true
        case .quit:
            break
        }
        return outcome
    }

    /// Applies a routed menu event. Returns the outcome when the event
    /// activated a row, nil otherwise. Cancel is Resume: the vanilla pause menu
    /// closes on the same key that opened it.
    @discardableResult
    public mutating func handle(_ event: MenuInputEvent) -> SystemMenuOutcome? {
        guard isOpen else { return nil }
        switch event {
        case let .move(direction):
            moveSelection(direction)
            return nil
        case .button(.accept):
            return activateSelection()
        case .button(.cancel):
            close()
            lastOutcome = .resume
            return .resume
        case .pointer, .release:
            return nil
        }
    }
}
