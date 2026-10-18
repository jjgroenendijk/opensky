// The gift menu `Actor.ShowGiftMenu` opens: the player gives items to an actor, or the
// actor gives items to the player. See docs/engine/inventory-menu.md#gift-menu.

import Foundation
import OpenSkyFormatsESM
import OpenSkyRendering

/// What the gift menu needs from the app.
public protocol GiftMenuWorld: MenuScreenWorld {
    /// The giver's items: the player's when `giving`, else the actor's.
    func giftCategories(actor: ReferenceKey, giving: Bool) -> [ItemListCategory]
    /// Moves one of `item` from the giver to the receiver; the outcome text.
    func give(_ item: FormID, actor: ReferenceKey, giving: Bool) -> String
    /// The actor the player stands closest to, for the sidebar.
    var nearestActor: ReferenceKey? { get }
}

public final class GiftMenuCoordinator: ItemListMenuScreen {
    public static let identifier: MenuIdentifier = "GiftMenu"
    public static let hint = "W/S: item   A/D: tab   E: give one   Esc: close"

    public private(set) var actor: ReferenceKey?
    public private(set) var isGiving = true
    private weak var world: (any GiftMenuWorld)?

    public init(
        menuMode: MenuModeController,
        movies: SWFMovieSource? = nil,
        hud: HUDCoordinator? = nil,
        world: (any GiftMenuWorld)? = nil
    ) {
        self.world = world
        super.init(
            identifier: Self.identifier,
            movie: (ItemListMenuMovieBridge.giftMoviePath, "Gift", Self.hint),
            menuMode: menuMode, layer: (movies, hud), world: world
        )
    }

    @discardableResult
    public func open(actor: ReferenceKey, giving: Bool) -> Bool {
        guard !isOpen, world != nil else { return false }
        self.actor = actor
        isGiving = giving
        lastResult = giving ? "Giving to \(actor)" : "Receiving from \(actor)"
        presentList()
        return true
    }

    @discardableResult
    public func openNearest() -> Bool {
        guard let actor = world?.nearestActor else {
            lastResult = "Not opened: no actor nearby"
            return false
        }
        return open(actor: actor, giving: true)
    }

    override func loadCategories() -> [ItemListCategory] {
        guard let actor else { return [] }
        return world?.giftCategories(actor: actor, giving: isGiving) ?? []
    }

    override func choose(_ row: ItemListRow, alternate _: Bool) -> String {
        guard let actor else { return "No actor" }
        return world?.give(FormID(row.tag), actor: actor, giving: isGiving) ?? "No game"
    }

    override func didClose() {
        actor = nil
    }
}
