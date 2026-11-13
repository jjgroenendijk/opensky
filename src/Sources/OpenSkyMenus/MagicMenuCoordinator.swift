// The magic menu: the player's known spells and powers by kind. Accept readies the
// selected spell in the right hand, R in the left. See docs/engine/magic.md#magic-menu.

import Foundation
public import OpenSkyMagicInterface
public import OpenSkyMenusInterface

/// What the magic menu needs from the app.
public protocol MagicMenuWorld: MenuScreenWorld {
    /// The known spells, grouped by the tabs the menu shows.
    var magicMenuCategories: [ItemListCategory] { get }
    /// Readies the known spell at `index`; the outcome text.
    func readySpell(at index: Int, leftHand: Bool) -> String
    /// What the unlock key does on the row at `index`; nil for a row that is no shout.
    func shoutUnlockStep(at index: Int) -> ShoutUnlockStep?
    func unlockShout(at index: Int) -> String
    func confirm(_ text: String, answer: @escaping (Bool) -> Void)
}

public final class MagicMenuCoordinator: ItemListMenuScreen {
    public static let identifier: MenuIdentifier = "MagicMenu"
    public static let hint = "W/S: spell   A/D: tab   E: right hand   R: left hand   Esc: close"
    private weak var world: (any MagicMenuWorld)?

    public init(
        menuMode: MenuModeController,
        movies: (any MenuMovieLoading)? = nil,
        hud: (any MenuLayerOwner)? = nil,
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

    /// The left-hand key on a shout unlocks its next word instead.
    override func choose(_ row: ItemListRow, alternate: Bool) -> String {
        guard let world else { return "No game" }
        let index = Int(row.tag)
        guard alternate, let step = world.shoutUnlockStep(at: index) else {
            return world.readySpell(at: index, leftHand: alternate)
        }
        switch step {
        case let .refuse(text):
            world.showHUDNotification(text)
            return text
        case let .ask(text):
            world.confirm(text) { [weak self] yes in
                guard yes, let self, let world = self.world else { return }
                lastResult = world.unlockShout(at: index)
                reload()
            }
            return text
        }
    }
}
