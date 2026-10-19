// The wait menu and the rest menu a bed opens. The movie owns the hours slider; the
// world passes the game time. See docs/engine/sleep-wait.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyRendering

/// What the sleep and wait menu needs from the app.
public protocol SleepWaitWorld: MenuScreenWorld {
    /// The date line, such as "Sundas, 1:00 PM, 17th of Last Seed, 4E 201"; nil without a game.
    var gameDateText: String? { get }
    /// The game's reason the player cannot rest or wait now; nil allows it. `bed` is
    /// the bed the player used, nil for the wait key.
    func restRefusal(sleeping: Bool, bed: FormID?) -> String?
    func passTime(hours: Int, sleeping: Bool)
}

public final class SleepWaitMenuCoordinator: MenuScreen<SleepWaitMovieEvent> {
    public static let identifier: MenuIdentifier = "Sleep/Wait Menu"
    /// The slider's range in the vanilla movie.
    public static let hours = 1 ... 24
    public static let hint = "A/D: hours   E or Enter: wait   Esc: cancel"

    public private(set) var isSleeping = false
    /// The hours the text panel shows; the movie keeps its own slider.
    public private(set) var chosenHours = 1
    private weak var world: (any SleepWaitWorld)?

    public init(
        menuMode: MenuModeController,
        movies: SWFMovieSource? = nil,
        hud: HUDCoordinator? = nil,
        world: (any SleepWaitWorld)? = nil
    ) {
        self.world = world
        super.init(
            identifier: Self.identifier, movieReadsKeys: true, menuMode: menuMode,
            layer: (movies, hud), world: world
        )
    }

    /// Opens the menu, or shows the game's refusal and stays shut.
    @discardableResult
    public func open(sleeping: Bool, bed: FormID? = nil) -> Bool {
        guard !isOpen else { return false }
        guard let world, let date = world.gameDateText else {
            lastResult = "Not opened: no game"
            return false
        }
        if let refusal = world.restRefusal(sleeping: sleeping, bed: bed) {
            lastResult = "Refused: \(refusal)"
            notify(refusal)
            return false
        }
        isSleeping = sleeping
        chosenHours = Self.hours.lowerBound
        lastResult = sleeping ? "Rest menu open" : "Wait menu open"
        present(
            path: SleepWaitMenuMovieBridge.moviePath,
            prepare: { [weak self] runtime in
                SleepWaitMenuMovieBridge.prepare(runtime: runtime) { self?.movie.post($0) }
            },
            activate: { runtime in
                SleepWaitMenuMovieBridge.activate(runtime: runtime, sleeping: sleeping, date: date)
            }
        )
        return true
    }

    override func handleKey(_ event: MenuInputEvent) {
        switch event {
        case .move(.left), .move(.down): chosenHours = max(Self.hours.lowerBound, chosenHours - 1)
        case .move(.right), .move(.up): chosenHours = min(Self.hours.upperBound, chosenHours + 1)
        case .button(.accept): handle(.wait(hours: chosenHours))
        case .button(.cancel): handle(.cancel)
        case .button(.xButton), .button(.yButton), .pointer, .release: return
        }
    }

    override func handle(_ event: SleepWaitMovieEvent) {
        switch event {
        case let .wait(hours):
            let clamped = min(max(hours, Self.hours.lowerBound), Self.hours.upperBound)
            close()
            world?.passTime(hours: clamped, sleeping: isSleeping)
            lastResult = "\(isSleeping ? "Rested" : "Waited") \(clamped) h"
        case .cancel:
            close()
            lastResult = "Cancelled"
        }
    }

    override func publishMovie(_ runtime: SWFMovieRuntime) {
        SleepWaitMenuMovieBridge.publish(
            sleeping: isSleeping, date: world?.gameDateText ?? "", runtime: runtime
        )
    }

    override var panel: MenuTextPanel {
        MenuTextPanel(
            title: isSleeping ? "Rest how long?" : "Wait how long?",
            lines: [world?.gameDateText ?? "", "\(chosenHours) h"],
            selection: 1,
            hint: Self.hint
        )
    }
}
