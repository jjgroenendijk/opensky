// Engine-owned menu-mode stack (todo 8.1.2). UI-toolkit-agnostic: identifiers
// are opaque names, so the future Scaleform SWF menu layer (M8.2) and the HUD
// drive the same stack without the engine knowing any concrete menu type. An
// empty stack means gameplay mode; a non-empty stack means menu mode (world sim
// paused, input routed to the menu layer). See docs/engine/menu-mode.md.

/// Opaque menu name. Mirrors Scaleform's string menu identity (for example
/// "InventoryMenu", "Console", "Dialogue Menu") without hardcoding any list;
/// the engine only compares identity, never interprets the name.
struct MenuIdentifier: Hashable {
    let name: String

    init(_ name: String) {
        self.name = name
    }
}

extension MenuIdentifier: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self.init(value)
    }
}

/// Ordered, duplicate-free stack of open menus. The top of the stack is the
/// focused menu that receives input first. Value type so callers can snapshot
/// and compare freely; `MenuModeController` owns the one live instance.
struct MenuStack: Equatable {
    private(set) var identifiers: [MenuIdentifier] = []

    var isEmpty: Bool {
        identifiers.isEmpty
    }

    var count: Int {
        identifiers.count
    }

    /// The focused menu (top of stack); nil in gameplay mode.
    var top: MenuIdentifier? {
        identifiers.last
    }

    /// True when at least one menu is open, i.e. menu mode is active.
    var isMenuMode: Bool {
        !identifiers.isEmpty
    }

    func contains(_ identifier: MenuIdentifier) -> Bool {
        identifiers.contains(identifier)
    }

    /// Pushes a menu onto the top. A menu name is unique in the stack because
    /// Scaleform opens one instance per name, so pushing a name already open is
    /// a no-op that returns false, letting the caller detect the rejected
    /// duplicate rather than stacking two of the same menu.
    @discardableResult
    mutating func push(_ identifier: MenuIdentifier) -> Bool {
        guard !identifiers.contains(identifier) else { return false }
        identifiers.append(identifier)
        return true
    }

    /// Pops the top menu. Returns the removed identifier, or nil when the stack
    /// is already empty, so a stray pop in gameplay mode is a harmless no-op.
    @discardableResult
    mutating func pop() -> MenuIdentifier? {
        identifiers.popLast()
    }

    /// Removes a specific menu regardless of its position, because Scaleform can
    /// close a menu by name while others stay open. Returns true when the menu
    /// was open.
    @discardableResult
    mutating func remove(_ identifier: MenuIdentifier) -> Bool {
        guard let index = identifiers.firstIndex(of: identifier) else { return false }
        identifiers.remove(at: index)
        return true
    }

    /// Closes every menu, returning to gameplay mode.
    mutating func removeAll() {
        identifiers.removeAll()
    }
}
