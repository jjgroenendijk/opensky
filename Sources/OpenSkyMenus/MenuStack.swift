public import OpenSkyMenusInterface

// Engine-owned menu stack (docs/engine/menu-mode.md). Identifiers are opaque
// names, so SWF menus and the HUD share it without the engine knowing a menu
// type. An empty stack is gameplay; a non-empty one pauses and routes input.

nonisolated extension MenuIdentifier: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}
