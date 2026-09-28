// Engine-owned menu mode (todo 8.1.2): owns the menu stack, decides whether
// input drives the world or the menu layer, and exposes the world-sim pause the
// renderer gates its per-frame time advance on. UI-toolkit-agnostic, so the
// future Scaleform SWF menu layer (M8.2) conforms to `MenuInputConsumer` and
// pushes/pops here without the engine knowing any concrete menu. See
// docs/engine/menu-mode.md.

/// Where an input event goes this frame.
nonisolated enum InputRoute: Equatable {
    /// Gameplay: keyboard movement and mouse look drive the free-fly/walk
    /// camera.
    case world
    /// Menu mode: world input is suppressed and events go to the menu layer.
    case menu
}

/// A menu event forwarded while menu mode is active. Deliberately small and
/// toolkit-free: directional focus moves, accept/cancel, and raw pointer motion
/// cover Scaleform menu navigation without binding to AppKit or a widget tree.
nonisolated enum MenuInputEvent: Equatable {
    enum Direction { case up, down, left, right }
    enum Button { case accept, cancel }

    case move(Direction)
    case button(Button)
    case pointer(deltaX: Float, deltaY: Float)
}

/// Implemented by the menu layer (none yet) to receive routed input.
protocol MenuInputConsumer: AnyObject {
    func handleMenuInput(_ event: MenuInputEvent)
}

/// What one open menu does to the world simulation.
///
/// Menu mode used to imply a paused world, which is true of the inventory, the
/// journal, the container and the system menu and false of exactly one menu
/// OpenSky now has: dialogue leaves the world running, which is what lets a
/// speaker keep breathing, walking and being heard while the player reads the
/// topic list.
///
/// No spec is cited for that, and none is needed: it follows from what the rest
/// of M17 has to do. Item 17.4's camera moves the view during a conversation,
/// 17.5 plays a voice line on a clock, and 17.6 and 17.7 drive face morphs from
/// that clock. Every one of them advances on the world sim, so stopping it here
/// would stop them.
///
/// A policy per menu rather than a flag on the controller because the two can
/// be open at once: the system menu over an open conversation still pauses,
/// and closing it hands the running world back to the dialogue underneath.
nonisolated enum MenuWorldPolicy: Equatable, Sendable {
    /// The world sim stops while this menu is open. Every menu before item
    /// 17.3, and the default, so a caller that does not think about it gets
    /// the behaviour it had.
    case pausesWorld
    /// Input is captured but the world keeps advancing.
    case leavesWorldRunning
}

/// Single source of truth for menu mode. The AppKit input layer asks
/// `currentRoute` before dispatching an event; the renderer reads
/// `isWorldSimPaused` each frame. Reference type: the view, the renderer, and
/// the menu layer share one instance, all on the main thread, so it needs no
/// internal locking (same threading contract as `Renderer`).
final class MenuModeController {
    private(set) var stack = MenuStack()

    /// The menu layer receiving routed events; nil until a menu layer exists, so
    /// menu-mode input is simply swallowed. World input stays suppressed in menu
    /// mode regardless of whether a consumer is attached.
    weak var inputConsumer: MenuInputConsumer?

    /// World policy of each menu that declared one, keyed by name. A menu
    /// absent from the table pauses, which is what every menu before item 17.3
    /// did and what a caller that never mentions a policy still gets.
    private var policies: [MenuIdentifier: MenuWorldPolicy] = [:]

    /// Called after every change to either the input route or the world-sim
    /// pause gate, with both new values. The app wires this to set the renderer
    /// pause gate and to drop held world input on entering menu mode.
    ///
    /// The two moved together until the dialogue menu, and no longer do: a
    /// non-pausing menu flips the route without flipping the pause, and a
    /// pausing menu opened over it flips the pause without flipping the route.
    /// Pushes and pops that change neither do not fire it.
    var onModeChange: ((_ route: InputRoute, _ worldSimPaused: Bool) -> Void)?

    var isMenuMode: Bool {
        stack.isMenuMode
    }

    /// The renderer's world-sim pause gate: true while any open menu declares
    /// `pausesWorld`. An open conversation alone leaves it false.
    var isWorldSimPaused: Bool {
        stack.identifiers.contains { policy(of: $0) == .pausesWorld }
    }

    /// The world policy one menu is open under, or the default for a menu that
    /// is not open.
    func policy(of identifier: MenuIdentifier) -> MenuWorldPolicy {
        policies[identifier] ?? .pausesWorld
    }

    var topMenu: MenuIdentifier? {
        stack.top
    }

    /// The routing decision for the AppKit input layer.
    var currentRoute: InputRoute {
        stack.isMenuMode ? .menu : .world
    }

    /// Opens a menu under `policy`. Entering menu mode from gameplay, or
    /// opening the first menu that pauses, fires `onModeChange`. A duplicate
    /// push (name already open) is rejected and returns false without firing
    /// the callback or rewriting the open menu's policy.
    @discardableResult
    func present(
        _ identifier: MenuIdentifier,
        policy: MenuWorldPolicy = .pausesWorld
    ) -> Bool {
        let previous = state
        guard stack.push(identifier) else { return false }
        policies[identifier] = policy
        notify(from: previous)
        return true
    }

    /// Closes the top menu. Fires `onModeChange` when that leaves gameplay
    /// mode or hands a running world back to a non-pausing menu underneath.
    /// Returns the removed identifier, or nil in gameplay.
    @discardableResult
    func dismissTop() -> MenuIdentifier? {
        let previous = state
        guard let removed = stack.pop() else { return nil }
        policies[removed] = nil
        notify(from: previous)
        return removed
    }

    /// Closes a specific menu by name regardless of stack position.
    @discardableResult
    func dismiss(_ identifier: MenuIdentifier) -> Bool {
        let previous = state
        guard stack.remove(identifier) else { return false }
        policies[identifier] = nil
        notify(from: previous)
        return true
    }

    /// Closes every menu, returning to gameplay mode. No-op in gameplay.
    func dismissAll() {
        guard stack.isMenuMode else { return }
        let previous = state
        stack.removeAll()
        policies.removeAll()
        notify(from: previous)
    }

    /// Forwards a menu event when in menu mode and returns true; a no-op that
    /// returns false in gameplay, so the caller can fall through to world input.
    /// The event is swallowed when no consumer is attached yet.
    @discardableResult
    func routeMenuInput(_ event: MenuInputEvent) -> Bool {
        guard stack.isMenuMode else { return false }
        inputConsumer?.handleMenuInput(event)
        return true
    }

    // MARK: - Change notification

    /// The pair the callback reports, sampled before and after a mutation so
    /// one comparison decides whether anything a listener cares about moved.
    private var state: (route: InputRoute, paused: Bool) {
        (currentRoute, isWorldSimPaused)
    }

    private func notify(from previous: (route: InputRoute, paused: Bool)) {
        let current = state
        guard current != previous else { return }
        onModeChange?(current.route, current.paused)
    }
}
