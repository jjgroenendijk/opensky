// Which spoken lines become text on screen, and when a line goes away. The
// player's two subtitle settings decide; the HUD movie draws the text.
// See docs/engine/settings.md.

import Foundation
public import OpenSkyMenusInterface

/// Draws or hides the one subtitle line. Nil hides it.
@MainActor
public protocol SubtitlePresenting: AnyObject {
    func presentSubtitle(_ text: String?)
}

@MainActor
public final class SubtitleCoordinator {
    public private(set) var settings = SubtitleSettings(dialogue: false, general: false)

    public private(set) var current: String?
    private var currentKind: SubtitleKind?
    private var shownUntil: Double = 0
    private weak let presenter: (any SubtitlePresenting)?

    public init(presenter: any SubtitlePresenting) {
        self.presenter = presenter
    }

    /// The player's subtitle switches; a line of a kind turned off goes away.
    public func apply(_ settings: SubtitleSettings) {
        self.settings = settings
        if let kind = currentKind, !settings.shows(kind) {
            clear()
        }
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
