// Main-app seam for the smaller menu screens: open one, and read what each did last.

import Foundation

/// A screen the sidebar can open.
nonisolated public enum MenuScreenKind: String, CaseIterable, Sendable {
    case wait = "Wait"
    case rest = "Rest"
    case training = "Training"
    case book = "Book"
    case help = "Help"
    case magic = "Magic"
    case gift = "Gift"
    case crafting = "Crafting"
    case map = "Map"
    case textEntry = "Text entry"
    case creationClub = "Creation Club"
}

/// One screen's readout line, such as `Wait: movie, Waited 3 h`.
nonisolated public struct MenuScreenReadout: Equatable, Sendable {
    public let kind: MenuScreenKind
    public let state: String
    public let lastResult: String

    public init(kind: MenuScreenKind, state: String, lastResult: String) {
        self.kind = kind
        self.state = state
        self.lastResult = lastResult
    }

    public var line: String {
        "\(kind.rawValue): \(state), \(lastResult)"
    }
}

@MainActor
public protocol MenuScreensControlProviding: AnyObject {
    var menuScreenReadouts: [MenuScreenReadout] { get }
    /// Opens `kind` on its sidebar target, such as the nearest trainer.
    @discardableResult
    func openMenuScreen(_ kind: MenuScreenKind) -> Bool
}
