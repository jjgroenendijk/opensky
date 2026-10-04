// Engine-owned system menu: the vanilla System page rows and which sub-page is
// open (docs/engine/system-menu.md). The model owns entries, selection, and
// activation, so keyboard input, the panel, and the movie bridge share one state.

import Foundation

/// One row of the system menu, in the vanilla order. Installed Content and Help
/// are left out: OpenSky has no online content and no help pages.
nonisolated public enum SystemMenuEntry: String, CaseIterable, Sendable {
    case resume
    case quicksave
    case save
    case load
    case settings
    case controls
    case quit

    public var title: String {
        switch self {
        case .resume: "Resume"
        case .quicksave: "Quicksave"
        case .save: "Save"
        case .load: "Load"
        case .settings: "Settings"
        case .controls: "Controls"
        case .quit: "Quit"
        }
    }

    /// Capitalized fragment used to build accessibility identifiers, so a row's
    /// control id is derived rather than written twice.
    public var identifierFragment: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

/// The page the menu shows. A sub-page has its own model in the coordinator.
nonisolated public enum SystemMenuPage: String, Equatable, Sendable {
    case main, settings, controls, save, load, quit
}

/// What activating a row asks the host to do.
nonisolated public enum SystemMenuOutcome: Equatable, Sendable {
    case resume
    case quicksave
    case showPage(SystemMenuPage)

    public var label: String {
        switch self {
        case .resume: "Resume"
        case .quicksave: "Quicksave"
        case let .showPage(page): page.rawValue.prefix(1).uppercased() + page.rawValue.dropFirst()
        }
    }
}

nonisolated public struct SystemMenuModel: Equatable, Sendable {
    public let entries: [SystemMenuEntry]
    public private(set) var isOpen = false
    public private(set) var selectedIndex = 0
    public private(set) var page = SystemMenuPage.main
    /// The last row activated while open, for the verification readout.
    public private(set) var lastOutcome: SystemMenuOutcome?

    public init(entries: [SystemMenuEntry] = SystemMenuEntry.allCases) {
        self.entries = entries.isEmpty ? SystemMenuEntry.allCases : entries
    }

    public var selectedEntry: SystemMenuEntry? {
        entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil
    }

    /// True while the Settings page is up.
    public var settingsRevealed: Bool {
        page == .settings
    }

    /// Opens the menu at the first row. Re-opening keeps the current state.
    public mutating func open() {
        guard !isOpen else { return }
        isOpen = true
        selectedIndex = 0
        page = .main
        lastOutcome = nil
    }

    public mutating func close() {
        isOpen = false
        selectedIndex = 0
        page = .main
    }

    /// Back from a sub-page to the row list.
    public mutating func showMain() {
        page = .main
    }

    /// Vertical moves wrap, as the vanilla list does. Horizontal moves are
    /// accepted and ignored, so the caller still counts the event as handled.
    public mutating func moveSelection(_ direction: MenuInputEvent.Direction) {
        guard isOpen, page == .main, !entries.isEmpty else { return }
        switch direction {
        case .up:
            selectedIndex = (selectedIndex + entries.count - 1) % entries.count
        case .down:
            selectedIndex = (selectedIndex + 1) % entries.count
        case .left, .right:
            break
        }
    }

    public mutating func select(_ entry: SystemMenuEntry) {
        if let index = entries.firstIndex(of: entry) {
            selectedIndex = index
        }
    }

    @discardableResult
    public mutating func activateSelection() -> SystemMenuOutcome? {
        guard isOpen, page == .main, let entry = selectedEntry else { return nil }
        let outcome: SystemMenuOutcome = switch entry {
        case .resume: .resume
        case .quicksave: .quicksave
        case .save: .showPage(.save)
        case .load: .showPage(.load)
        case .settings: .showPage(.settings)
        case .controls: .showPage(.controls)
        case .quit: .showPage(.quit)
        }
        lastOutcome = outcome
        switch outcome {
        case .resume:
            close()
        case let .showPage(next):
            page = next
        case .quicksave:
            break
        }
        return outcome
    }

    /// The main page's events. Cancel there is Resume: the vanilla pause menu
    /// closes on the key that opened it. A sub-page handles its own events.
    @discardableResult
    public mutating func handle(_ event: MenuInputEvent) -> SystemMenuOutcome? {
        guard isOpen, page == .main else { return nil }
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
