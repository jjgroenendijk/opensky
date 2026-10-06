// Which spoken lines become text on screen, and when a line goes away. The
// player's two subtitle settings decide; the HUD movie draws the text.
// See docs/engine/settings.md.

import Foundation

nonisolated public enum SubtitleKind: Sendable {
    /// A line in a conversation the player is in.
    case dialogue
    /// A line spoken near the player outside a conversation, such as a scene.
    case general
}

nonisolated public struct SubtitleSettings: Equatable, Sendable {
    public var dialogue: Bool
    public var general: Bool

    public init(dialogue: Bool, general: Bool) {
        self.dialogue = dialogue
        self.general = general
    }

    public func shows(_ kind: SubtitleKind) -> Bool {
        switch kind {
        case .dialogue: dialogue
        case .general: general
        }
    }
}

/// Draws or hides the one subtitle line. Nil hides it.
@MainActor
public protocol SubtitlePresenting: AnyObject {
    func presentSubtitle(_ text: String?)
}

@MainActor
public final class SubtitleCoordinator {
    public var settings = SubtitleSettings(dialogue: false, general: false) {
        didSet {
            if let kind = currentKind, !settings.shows(kind) {
                clear()
            }
        }
    }

    public private(set) var current: String?
    private var currentKind: SubtitleKind?
    private var shownUntil: Double = 0
    private weak var presenter: (any SubtitlePresenting)?

    public init() {}

    public func attach(presenter: any SubtitlePresenting) {
        self.presenter = presenter
    }

    /// Shows the line for `seconds` when the setting for its kind is on.
    @discardableResult
    public func say(_ text: String, kind: SubtitleKind, seconds: Double, now: Double) -> Bool {
        guard settings.shows(kind), !text.isEmpty else { return false }
        current = text
        currentKind = kind
        shownUntil = now + seconds
        presenter?.presentSubtitle(text)
        return true
    }

    public func advance(to now: Double) {
        guard current != nil, now >= shownUntil else { return }
        clear()
    }

    public func clear() {
        guard current != nil else { return }
        current = nil
        currentKind = nil
        presenter?.presentSubtitle(nil)
    }
}
