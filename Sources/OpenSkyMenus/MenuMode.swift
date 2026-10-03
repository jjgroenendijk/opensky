// Engine-owned menu mode (docs/engine/menu-mode.md): owns the menu stack,
// routes input to the world or the menus, and exposes the world-sim pause.
// Menus conform to `MenuInputConsumer`, so the engine knows no concrete menu.

/// Where an input event goes this frame.
nonisolated public enum InputRoute: Equatable, Sendable {
    /// Gameplay: keyboard movement and mouse look drive the free-fly/walk
    /// camera.
    case world
    /// Menu mode: world input is suppressed and events go to the menu layer.
    case menu
}

/// A menu event forwarded while menu mode is active. Deliberately small and
/// toolkit-free: directional focus moves, accept/cancel, and raw pointer motion
/// cover Scaleform menu navigation without binding to AppKit or a widget tree.
nonisolated public enum MenuInputEvent: Equatable, Sendable {
    public enum Direction: Sendable { case up, down, left, right }
    public enum Button: Sendable { case accept, cancel }

    case move(Direction)
    case button(Button)
    case pointer(deltaX: Float, deltaY: Float)
    /// A direction key came up. Only a menu that reads held keys, such as
    /// lockpicking, acts on it.
    case release(Direction)
}

/// Implemented by the menu layer (none yet) to receive routed input.
public protocol MenuInputConsumer: AnyObject {
    func handleMenuInput(_ event: MenuInputEvent)
}

/// What one open menu does to the world simulation. Dialogue leaves it
/// running, because its camera, voice clock, and face morphs advance on it.
/// A per-menu policy, because a pausing menu can open over dialogue.
nonisolated public enum MenuWorldPolicy: Equatable, Sendable {
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
public final class MenuModeController {
    public init() {}

    public private(set) var stack = MenuStack()

    /// The menu layer receiving routed events; nil until a menu layer exists, so
    /// menu-mode input is simply swallowed. World input stays suppressed in menu
    /// mode regardless of whether a consumer is attached.
    public weak var inputConsumer: MenuInputConsumer?

    /// World policy of each menu that declared one, keyed by name. A menu absent from the
    /// table pauses, which is the default for a caller that names no policy.
    private var policies: [MenuIdentifier: MenuWorldPolicy] = [:]

    /// Called after a change to the input route or the world-sim pause, with
    /// both values. The two can change apart: dialogue flips only the route.
    /// The app sets the renderer pause and drops held world input.
    public var onModeChange: ((_ route: InputRoute, _ worldSimPaused: Bool) -> Void)?

    public var isMenuMode: Bool {
        stack.isMenuMode
    }

    /// The renderer's world-sim pause gate: true while any open menu declares
    /// `pausesWorld`. An open conversation alone leaves it false.
    public var isWorldSimPaused: Bool {
        stack.identifiers.contains { policy(of: $0) == .pausesWorld }
    }

    /// The world policy one menu is open under, or the default for a menu that
    /// is not open.
    public func policy(of identifier: MenuIdentifier) -> MenuWorldPolicy {
        policies[identifier] ?? .pausesWorld
    }

    public var topMenu: MenuIdentifier? {
        stack.top
    }

    /// The routing decision for the AppKit input layer.
    public var currentRoute: InputRoute {
        stack.isMenuMode ? .menu : .world
    }

    /// Opens a menu under `policy`. Entering menu mode from gameplay, or
    /// opening the first menu that pauses, fires `onModeChange`. A duplicate
    /// push (name already open) is rejected and returns false without firing
    /// the callback or rewriting the open menu's policy.
    @discardableResult
    public func present(
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
    public func dismissTop() -> MenuIdentifier? {
        let previous = state
        guard let removed = stack.pop() else { return nil }
        policies[removed] = nil
        notify(from: previous)
        return removed
    }

    /// Closes a specific menu by name regardless of stack position.
    @discardableResult
    public func dismiss(_ identifier: MenuIdentifier) -> Bool {
        let previous = state
        guard stack.remove(identifier) else { return false }
        policies[identifier] = nil
        notify(from: previous)
        return true
    }

    /// Closes every menu, returning to gameplay mode. No-op in gameplay.
    public func dismissAll() {
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
    public func routeMenuInput(_ event: MenuInputEvent) -> Bool {
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
