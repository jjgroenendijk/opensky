// The book menu: a book or note opens on its text, from the inventory or where it lies.
// Reading a skill book or a spell tome takes effect when it opens. See docs/engine/books.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsSWF

/// One book's text, ready for the movie.
nonisolated public struct BookContent: Equatable, Sendable {
    public var title: String
    /// The record's text, with the game's HTML tags.
    public var text: String
    public var isNote: Bool

    public init(title: String, text: String, isNote: Bool) {
        self.title = title
        self.text = text
        self.isNote = isNote
    }
}

/// A book read where it lies: the bar offers to take it.
public struct BookTakeOffer {
    public var isTheft: Bool
    /// The placed book, so its scripts get `OnRead`.
    public var reference: FormID?
    public var take: () -> Void

    public init(isTheft: Bool, reference: FormID? = nil, take: @escaping () -> Void) {
        self.isTheft = isTheft
        self.reference = reference
        self.take = take
    }
}

/// What the book menu needs from the app.
public protocol BookMenuWorld: MenuScreenWorld {
    func bookContent(_ item: FormID) -> BookContent?
    /// Applies what reading teaches; the notice to show, or nil when it teaches nothing.
    func readBook(_ item: FormID) -> String?
    /// The books and notes the player carries.
    var carriedBooks: [FormID] { get }
    /// The book opened: Papyrus `OnRead` on the placed `reference`, or on the item.
    func noteBookRead(_ item: FormID, reference: FormID?)
}

extension BookMenuWorld {
    public func noteBookRead(_: FormID, reference _: FormID?) {}
}

public final class BookMenuCoordinator: MenuScreen<Never> {
    public static let identifier: MenuIdentifier = "Book Menu"
    public static let hint = "A/D: turn page   Tab or Esc: close"

    public private(set) var content: BookContent?
    /// The first line the text panel shows.
    public private(set) var panelLine = 0
    public private(set) var takeOffer: BookTakeOffer?
    /// `bookmenu.swf`, the button bar over the pages.
    public let bar: MenuMovieOverlay
    private weak var world: (any BookMenuWorld)?

    public init(
        menuMode: MenuModeController,
        movies: SWFMovieSource? = nil,
        hud: HUDCoordinator? = nil,
        world: (any BookMenuWorld)? = nil
    ) {
        self.world = world
        bar = MenuMovieOverlay(movies: movies) { [weak world] in world?.renderer }
        super.init(
            identifier: Self.identifier, movieReadsKeys: false, menuMode: menuMode,
            layer: (movies, hud), world: world
        )
    }

    @discardableResult
    public func open(item: FormID, takeOffer: BookTakeOffer? = nil) -> Bool {
        guard !isOpen else { return false }
        guard let content = world?.bookContent(item) else {
            lastResult = "Not opened: \(item) is not a book"
            return false
        }
        self.content = content
        self.takeOffer = takeOffer
        panelLine = 0
        if let notice = world?.readBook(item) {
            notify(notice)
        }
        world?.noteBookRead(item, reference: takeOffer?.reference)
        lastResult = "Reading: \(content.title)"
        present(path: BookMenuMovieBridge.moviePath, activate: { runtime in
            BookMenuMovieBridge.activate(
                runtime: runtime, text: content.text, isNote: content.isNote
            )
        })
        let button = takeButton
        bar.start(
            path: BookMenuBarMovieBridge.moviePath,
            prepare: BookMenuBarMovieBridge.prepare(runtime:)
        ) { BookMenuBarMovieBridge.activate(runtime: $0, take: button) }
        return true
    }

    public func isBook(_ item: FormID) -> Bool {
        world?.bookContent(item) != nil
    }

    /// Opens the first carried book.
    @discardableResult
    public func openFirstCarried() -> Bool {
        guard let item = world?.carriedBooks.first else {
            lastResult = "Not opened: no book carried"
            return false
        }
        return open(item: item)
    }

    override func handleKey(_ event: MenuInputEvent) {
        switch event {
        case .move(.left), .move(.up): turn(forward: false)
        case .move(.right), .move(.down): turn(forward: true)
        case .button(.accept): take()
        case .button(.cancel): close()
        default: return
        }
    }

    public var takeButton: BookTakeButton {
        guard let takeOffer else { return .hidden }
        return takeOffer.isTheft ? .steal : .take
    }

    override public func tick(now: Double) {
        super.tick(now: now)
        bar.tick()
    }

    /// Takes a book read where it lies, then closes; a carried book only closes.
    private func take() {
        if let takeOffer, let title = content?.title {
            takeOffer.take()
            lastResult = "\(takeOffer.isTheft ? "Stole" : "Took"): \(title)"
        }
        close()
    }

    private func turn(forward: Bool) {
        let isNote = content?.isNote ?? false
        if movie.isLoaded {
            movie.publish {
                BookMenuMovieBridge.turnPage(forward: forward, isNote: isNote, runtime: $0)
            }
            return
        }
        let step = forward ? MenuTextPanel.shownLines : -MenuTextPanel.shownLines
        panelLine = max(0, min(panelLine + step, max(0, panelLines.count - 1)))
    }

    override func didClose() {
        bar.stop()
        content = nil
        takeOffer = nil
    }

    private var panelLines: [String] {
        SWFEditText.stripHTML(content?.text ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    override var panel: MenuTextPanel {
        let lines = panelLines
        let shown = lines.dropFirst(panelLine).prefix(MenuTextPanel.shownLines)
        let hint = switch takeButton {
        case .hidden: Self.hint
        case .take: "E: take   \(Self.hint)"
        case .steal: "E: steal   \(Self.hint)"
        }
        return MenuTextPanel(title: content?.title ?? "", lines: Array(shown), hint: hint)
    }
}
