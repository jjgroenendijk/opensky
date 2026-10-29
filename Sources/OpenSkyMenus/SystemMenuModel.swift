// Engine-owned system menu: the vanilla System page rows and which sub-page is
// open (docs/engine/system-menu.md). The model owns entries, selection, and
// activation, so keyboard input, the readout, and the movie bridge share one state.

import Foundation

/// One row of the system menu, in the vanilla order.
nonisolated public enum SystemMenuEntry: String, CaseIterable, Sendable {
    case resume
    case quicksave
    case save
    case load
    case installedContent
    case settings
    case controls
    case help
    case quit

    public var title: String {
        switch self {
        case .resume: "Resume"
        case .quicksave: "Quicksave"
        case .save: "Save"
        case .load: "Load"
        case .installedContent: "Installed Content"
        case .settings: "Settings"
        case .controls: "Controls"
        case .help: "Help"
        case .quit: "Quit"
        }
    }

    /// What activating the row asks the host to do.
    public var outcome: SystemMenuOutcome {
        switch self {
        case .resume: .resume
        case .quicksave: .quicksave
        case .save: .showPage(.save)
        case .load: .showPage(.load)
        case .installedContent: .showPage(.installedContent)
        case .settings: .showPage(.settings)
        case .controls: .showPage(.controls)
        case .help: .showPage(.help)
        case .quit: .showPage(.quit)
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
    case main, settings, controls, save, load, quit, installedContent, help

    /// The Help and Installed Content pages: a topic list and the text of one topic.
    public var isTopicPage: Bool {
        self == .installedContent || self == .help
    }
}

nonisolated extension SystemMenuPage {
    /// The rawValue with its first letter capitalized, such as "InstalledContent".
    public var label: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
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
        case let .showPage(page): page.label
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

    /// The movie opened a page by itself.
    public mutating func show(_ page: SystemMenuPage) {
        guard isOpen else { return }
        self.page = page
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
        let outcome = entry.outcome
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
        case .button(.xButton), .button(.yButton), .pointer, .release:
            return nil
        }
    }
}
