// The magic menu: the player's known spells and powers by kind. Accept readies the
// selected spell in the right hand, R in the left. See docs/engine/magic.md#magic-menu.

import Foundation
import OpenSkyRendering

/// What the magic menu needs from the app.
public protocol MagicMenuWorld: MenuScreenWorld {
    /// The known spells, grouped by the tabs the menu shows.
    var magicMenuCategories: [ItemListCategory] { get }
    /// Readies the known spell at `index`; the outcome text.
    func readySpell(at index: Int, leftHand: Bool) -> String
}

public final class MagicMenuCoordinator: ItemListMenuScreen {
    public static let identifier: MenuIdentifier = "MagicMenu"
    public static let hint = "W/S: spell   A/D: tab   E: right hand   R: left hand   Esc: close"
    private weak var world: (any MagicMenuWorld)?

    public init(
        menuMode: MenuModeController,
        movies: SWFMovieSource? = nil,
        hud: HUDCoordinator? = nil,
        world: (any MagicMenuWorld)? = nil
    ) {
        self.world = world
        super.init(
            identifier: Self.identifier,
            movie: ItemListScreenMovie(
                path: ItemListMenuMovieBridge.magicMoviePath, title: "Magic", hint: Self.hint
            ),
            menuMode: menuMode, layer: (movies, hud), world: world
        )
    }

    @discardableResult
    public func open() -> Bool {
        guard !isOpen, world != nil else { return false }
        lastResult = "Open"
        presentList()
        return true
    }

    override func loadCategories() -> [ItemListCategory] {
        world?.magicMenuCategories ?? []
    }

    override func choose(_ row: ItemListRow, alternate: Bool) -> String {
        world?.readySpell(at: Int(row.tag), leftHand: alternate) ?? "No game"
    }
}
