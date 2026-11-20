// Which open menus blur the world behind them with the `IMID` image space modifier.
// See docs/engine/tween-menu.md#blur.

public import OpenSkyMenusInterface

public enum MenuBlur {
    /// The menus that take the modifier. One modifier serves them all.
    public static let menus: Set<MenuIdentifier> = [
        TweenMenuCoordinator.identifier, .inventoryMenu, MagicMenuCoordinator.identifier
    ]

    /// True while any open menu blurs the world.
    public static func wanted(open: [MenuIdentifier]) -> Bool {
        open.contains(where: menus.contains)
    }
}
