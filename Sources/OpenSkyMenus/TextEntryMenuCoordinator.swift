// A one-line name field. Typed characters arrive from the game view; Enter accepts and
// Esc cancels. See docs/engine/text-entry.md.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyRendering

public final class TextEntryMenuCoordinator: MenuScreen<Bool> {
    public static let identifier: MenuIdentifier = "TextEntry Menu"
    public static let hint = "Type a name   Enter: accept   Esc: cancel"
    public static let lengthLimit = 64

    public private(set) var text = ""
    private var title = ""
    private var onFinish: ((String?) -> Void)?

    public init(
        menuMode: MenuModeController,
        movies: SWFMovieSource? = nil,
        hud: HUDCoordinator? = nil,
        world: (any MenuScreenWorld)? = nil
    ) {
        super.init(
            identifier: Self.identifier, movieReadsKeys: false, menuMode: menuMode,
            layer: (movies, hud), world: world
        )
    }

    /// `onFinish` gets the accepted text, or nil when the player cancels.
    @discardableResult
    public func open(
        title: String, text: String = "", onFinish: ((String?) -> Void)? = nil
    ) -> Bool {
        guard !isOpen else { return false }
        self.title = title
        self.text = String(text.prefix(Self.lengthLimit))
        self.onFinish = onFinish
        present(path: TextEntryMenuMovieBridge.moviePath) { [weak self] runtime in
            TextEntryMenuMovieBridge.activate(runtime: runtime) { self?.movie.post($0) }
        }
        return true
    }

    /// Typed characters; false while closed, so the key goes elsewhere.
    public func type(_ characters: String) -> Bool {
        guard isOpen else { return false }
        for character in characters {
            if character == "\u{7F}" || character == "\u{8}" {
                if !text.isEmpty {
                    text.removeLast()
                }
            } else if !character.isNewline, text.count < Self.lengthLimit {
                text.append(character)
            }
        }
        publish()
        return true
    }

    override func handleKey(_ event: MenuInputEvent) {
        let accept: Bool
        switch event {
        case .button(.accept): accept = true
        case .button(.cancel): accept = false
        default: return
        }
        if movie.isLoaded {
            movie.publish { TextEntryMenuMovieBridge.press(accept: accept, runtime: $0) }
        } else if !accept || !text.isEmpty {
            handle(accept)
        }
    }

    override func handle(_ accepted: Bool) {
        let result = accepted ? text : nil
        lastResult = result.map { "Entered \($0)" } ?? "Cancelled"
        let finish = onFinish
        close()
        finish?(result)
    }

    override func didClose() {
        onFinish = nil
    }

    override func publishMovie(_ runtime: SWFMovieRuntime) {
        TextEntryMenuMovieBridge.publish(text: text, runtime: runtime)
    }

    override var panel: MenuTextPanel {
        MenuTextPanel(title: title, lines: ["\(text)_"], hint: Self.hint)
    }
}
