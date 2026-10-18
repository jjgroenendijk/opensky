// The gift menu `Actor.ShowGiftMenu` opens: the player gives items to an actor, or the
// actor gives items to the player. See docs/engine/inventory-menu.md#gift-menu.

import Foundation
import OpenSkyFormatsESM
import OpenSkyRendering

/// The arguments of `Actor.ShowGiftMenu` (CK wiki "ShowGiftMenu - Actor").
nonisolated public struct GiftMenuRequest: Equatable, Sendable {
    /// True: the player gives. False: the actor gives.
    public var giving: Bool
    /// Items and keywords a shown item must match; nil shows every item.
    public var filter: Set<ReferenceKey>?
    public var showsStolenItems: Bool

    public init(giving: Bool, filter: Set<ReferenceKey>? = nil, showsStolenItems: Bool = false) {
        self.giving = giving
        self.filter = filter
        self.showsStolenItems = showsStolenItems
    }

    /// `identities` are the item itself and its keywords.
    public func shows(stolen: Bool, identities: Set<ReferenceKey>) -> Bool {
        guard showsStolenItems || !stolen else { return false }
        return filter.map { !$0.isDisjoint(with: identities) } ?? true
    }
}

/// What the gift menu needs from the app.
public protocol GiftMenuWorld: MenuScreenWorld {
    /// The giver's items: the player's when giving, else the actor's.
    func giftCategories(actor: ReferenceKey, request: GiftMenuRequest) -> [ItemListCategory]
    /// Moves one of `item` from the giver to the receiver; the outcome text.
    func give(_ item: FormID, actor: ReferenceKey, giving: Bool) -> String
    /// The actor the player stands closest to, for the sidebar.
    var nearestActor: ReferenceKey? { get }
}

public final class GiftMenuCoordinator: ItemListMenuScreen {
    public static let identifier: MenuIdentifier = "GiftMenu"
    public static let hint = "W/S: item   A/D: tab   E: give one   Esc: close"

    public private(set) var actor: ReferenceKey?
    public private(set) var request = GiftMenuRequest(giving: true)
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
            movie: ItemListScreenMovie(
                path: ItemListMenuMovieBridge.giftMoviePath, title: "Gift", hint: Self.hint
            ),
            menuMode: menuMode, layer: (movies, hud), world: world
        )
    }

    @discardableResult
    public func open(actor: ReferenceKey, request: GiftMenuRequest) -> Bool {
        guard !isOpen, world != nil else { return false }
        self.actor = actor
        self.request = request
        lastResult = request.giving ? "Giving to \(actor)" : "Receiving from \(actor)"
        presentList()
        return true
    }

    @discardableResult
    public func openNearest() -> Bool {
        guard let actor = world?.nearestActor else {
            lastResult = "Not opened: no actor nearby"
            return false
        }
        return open(actor: actor, request: GiftMenuRequest(giving: true))
    }

    override func loadCategories() -> [ItemListCategory] {
        guard let actor else { return [] }
        return world?.giftCategories(actor: actor, request: request) ?? []
    }

    override func choose(_ row: ItemListRow, alternate _: Bool) -> String {
        guard let actor else { return "No actor" }
        return world?.give(FormID(row.tag), actor: actor, giving: request.giving) ?? "No game"
    }

    override func didClose() {
        actor = nil
    }
}
