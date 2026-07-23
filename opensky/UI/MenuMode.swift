// Engine-owned menu mode (todo 8.1.2): owns the menu stack, decides whether
// input drives the world or the menu layer, and exposes the world-sim pause the
// renderer gates its per-frame time advance on. UI-toolkit-agnostic, so the
// future Scaleform SWF menu layer (M8.2) conforms to `MenuInputConsumer` and
// pushes/pops here without the engine knowing any concrete menu. See
// docs/engine/menu-mode.md.

/// Where an input event goes this frame.
enum InputRoute: Equatable {
    /// Gameplay: keyboard movement and mouse look drive the free-fly/walk
    /// camera.
    case world
    /// Menu mode: world input is suppressed and events go to the menu layer.
    case menu
}

/// A menu event forwarded while menu mode is active. Deliberately small and
/// toolkit-free: directional focus moves, accept/cancel, and raw pointer motion
/// cover Scaleform menu navigation without binding to AppKit or a widget tree.
enum MenuInputEvent: Equatable {
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

    /// Called after every change that flips the mode between gameplay and menu,
    /// with the new world-sim pause state. The app wires this to set the
    /// renderer pause gate and drop held world input. Pushes and pops that leave
    /// the mode unchanged (menu to menu) do not fire it.
    var onModeChange: ((_ worldSimPaused: Bool) -> Void)?

    var isMenuMode: Bool {
        stack.isMenuMode
    }

    /// The renderer's world-sim pause gate: true exactly in menu mode.
    var isWorldSimPaused: Bool {
        stack.isMenuMode
    }

    var topMenu: MenuIdentifier? {
        stack.top
    }

    /// The routing decision for the AppKit input layer.
    var currentRoute: InputRoute {
        stack.isMenuMode ? .menu : .world
    }

    /// Opens a menu. Entering menu mode from gameplay fires `onModeChange(true)`.
    /// A duplicate push (name already open) is rejected and returns false
    /// without firing the callback.
    @discardableResult
    func present(_ identifier: MenuIdentifier) -> Bool {
        let wasMenuMode = stack.isMenuMode
        guard stack.push(identifier) else { return false }
        if !wasMenuMode {
            onModeChange?(true)
        }
        return true
    }

    /// Closes the top menu. Closing the last open menu fires
    /// `onModeChange(false)`; closing an inner menu leaves menu mode active and
    /// does not fire it. Returns the removed identifier, or nil in gameplay.
    @discardableResult
    func dismissTop() -> MenuIdentifier? {
        let removed = stack.pop()
        if removed != nil, !stack.isMenuMode {
            onModeChange?(false)
        }
        return removed
    }

    /// Closes a specific menu by name regardless of stack position. Fires
    /// `onModeChange(false)` only when this removal empties the stack.
    @discardableResult
    func dismiss(_ identifier: MenuIdentifier) -> Bool {
        let removed = stack.remove(identifier)
        if removed, !stack.isMenuMode {
            onModeChange?(false)
        }
        return removed
    }

    /// Closes every menu, returning to gameplay mode. No-op in gameplay.
    func dismissAll() {
        guard stack.isMenuMode else { return }
        stack.removeAll()
        onModeChange?(false)
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
}
