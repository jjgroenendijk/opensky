// The Tween menu, which the Tween Menu key (Tab) opens over the paused world. Its four
// entries open the skills, magic, item, and map menus. See docs/engine/tween-menu.md.

import Foundation
import OpenSkyFormatsSWF
public import OpenSkyMenusInterface

/// What the Tween menu needs from the app.
public protocol TweenMenuWorld: MenuScreenWorld {
    /// The date line, such as "Sundas, 1:00 PM, 17th of Last Seed, 4E 201"; nil without a game.
    var gameDateText: String? { get }
    var tweenLevel: TweenMenuLevel { get }
}

/// The player's level as the bottom bar shows it.
nonisolated public struct TweenMenuLevel: Equatable, Sendable {
    public var level: Int
    /// Experience toward the next level, 0 to 1.
    public var progress: Float
    public var levelUpReady: Bool

    public init(level: Int, progress: Float, levelUpReady: Bool) {
        self.level = level
        self.progress = progress
        self.levelUpReady = levelUpReady
    }
}

public final class TweenMenuCoordinator: MenuScreen<TweenMovieEvent> {
    public static let identifier: MenuIdentifier = "TweenMenu"
    static let hint = "Arrows: choose   E or Enter: open   Tab or Esc: close"

    /// The entry the movie or the arrow keys highlight last; nil before the first.
    public private(set) var highlighted: TweenMenuChoice?
    /// The Skills entry reads "LEVEL UP" while a level waits.
    public private(set) var showsLevelUp = false
    /// The close animation runs; the menu shuts when it ends.
    public private(set) var isClosing = false
    private var onChoose: ((TweenMenuChoice) -> Void)?
    private weak var world: (any TweenMenuWorld)?

    public init(
        menuMode: MenuModeController,
        movies: (any MenuMovieLoading)? = nil,
        hud: (any MenuLayerOwner)? = nil,
        world: (any TweenMenuWorld)? = nil
    ) {
        self.world = world
        super.init(
            identifier: Self.identifier, movieReadsKeys: true, menuMode: menuMode,
            layer: (movies, hud), world: world
        )
    }

    /// Opens the menu. `onChoose` opens the chosen menu once this one has shut.
    @discardableResult
    public func open(onChoose: @escaping (TweenMenuChoice) -> Void) -> Bool {
        guard !isOpen else { return false }
        guard let world, let date = world.gameDateText else {
            lastResult = "Not opened: no game"
            return false
        }
        let level = world.tweenLevel
        let content = TweenMenuContent(
            date: date, level: level.level, levelProgress: level.progress,
            levelUpReady: level.levelUpReady
        )
        showsLevelUp = level.levelUpReady
        highlighted = nil
        isClosing = false
        self.onChoose = onChoose
        lastResult = "Tween menu open"
        present(
            path: TweenMenuMovieBridge.moviePath,
            prepare: { [weak self] runtime in
                TweenMenuMovieBridge.prepare(runtime: runtime) { self?.movie.post($0) }
            },
            activate: { TweenMenuMovieBridge.activate(runtime: $0, content: content) }
        )
        return true
    }

    /// The arrows pick the entry that sits that way: Skills up, Magic left, Items right,
    /// Map down. The movie handles them itself while it is loaded.
    static func choice(toward direction: MenuInputEvent.Direction) -> TweenMenuChoice {
        switch direction {
        case .up: .skills
        case .left: .magic
        case .right: .items
        case .down: .map
        }
    }

    override func handleKey(_ event: MenuInputEvent) {
        switch event {
        case .button(.cancel): startClosing()
        case let .move(direction): highlighted = Self.choice(toward: direction)
        case .button(.accept): highlighted.map(choose)
        default: return
        }
    }

    override func handle(_ event: TweenMovieEvent) {
        switch event {
        case let .highlight(choice): highlighted = choice
        case let .open(choice): choose(choice)
        case .closing: isClosing = true
        case .closed:
            close()
            lastResult = "Closed"
        }
    }

    override func didClose() {
        isClosing = false
    }

    override var panel: MenuTextPanel {
        let lines = TweenMenuChoice.allCases.map { choice in
            choice == .skills && showsLevelUp ? "Level up" : "\(choice)".capitalized
        }
        return MenuTextPanel(
            title: "Tween menu", lines: lines,
            selection: highlighted.flatMap { TweenMenuChoice.allCases.firstIndex(of: $0) },
            hint: Self.hint
        )
    }

    /// The movie plays its close animation and then calls `CloseMenu`.
    private func startClosing() {
        guard !isClosing else { return }
        guard movie.isLoaded else {
            close()
            lastResult = "Closed"
            return
        }
        isClosing = true
        movie.publish { TweenMenuMovieBridge.startClose(runtime: $0) }
    }

    private func choose(_ choice: TweenMenuChoice) {
        guard !isClosing else { return }
        let onChoose = onChoose
        close()
        lastResult = "Opened \(choice)"
        onChoose?(choice)
    }
}
