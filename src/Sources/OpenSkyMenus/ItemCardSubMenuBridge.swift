// The item card's sub-menus that the inventory, container, and barter movies share:
// the quantity slider (`ShowQuantityMenu`) and the confirm message
// (`ShowConfirmMessage`). Both read `ENTER` to accept and `TAB` to cancel in the
// card's own input handler. See docs/engine/inventory-menu.md#quantity.

import Foundation
public import OpenSkyFormatsSWF
public import OpenSkyMenusInterface
public import OpenSkyRendering

nonisolated public enum ItemCardSubMenuBridge: Sendable {
    /// The same path in all three movies, after the import merge.
    public static let itemCardPath = "/Menu_mc/ItemCardFadeHolder_mc/ItemCard_mc"
    /// `InventoryLists_mc`, which holds both list panels.
    public static let listsPath = "/Menu_mc/InventoryLists_mc"
    /// `BarterMenu.iConfirmAmount`: what `onTransactionConfirm` sells.
    public static let confirmAmountName = "iConfirmAmount"
    public static let menuPath = "/Menu_mc"

    /// `InventoryLists.ShowItemsList(abPlayBladeSound, abPlayAnim)`: the item panel
    /// opens beside the categories (`TWO_PANELS`). The card fades in, and the movie
    /// asks for the 3D item through `UpdateItem3D(true)`.
    public static func showItemsList(runtime: SWFMovieRuntime) {
        runtime.callMovie(
            "ShowItemsList", atPath: listsPath, arguments: [.boolean(false), .boolean(true)]
        )
    }

    /// `InventoryLists.iCurrentState`: 0 no panels, 1 one, 2 two, then the transitions.
    public static func listsState(runtime: SWFMovieRuntime) -> Int? {
        guard
            let lists = runtime.node(atPath: listsPath, from: runtime.root),
            case let .number(state) = lists.object.lookup("iCurrentState")?.property.value
        else { return nil }
        return Int(state)
    }

    /// Opens the slider at `maximum`, which is also where it starts.
    public static func showQuantity(maximum: Int, runtime: SWFMovieRuntime) {
        runtime.callMovie(
            "ShowQuantityMenu", atPath: itemCardPath, arguments: [.integer(maximum)]
        )
    }

    /// Opens the confirm message. On the barter menu, accept sells `amount`.
    public static func showConfirm(_ text: String, amount: Int, runtime: SWFMovieRuntime) {
        runtime.node(atPath: menuPath, from: runtime.root)?.object
            .assign(.integer(amount), for: confirmAmountName)
        runtime.callMovie(
            "ShowConfirmMessage", atPath: itemCardPath, arguments: [.string(text)]
        )
    }

    /// The key a menu event sends while a sub-menu is open. Left and right move
    /// the focused slider.
    public static func key(for event: MenuInputEvent) -> (code: Int, ascii: Int)? {
        switch event {
        case .move(.left): (SWFKeyCode.left, 0)
        case .move(.right): (SWFKeyCode.right, 0)
        case .button(.accept), .button(.xButton): (SWFKeyCode.enter, 13)
        case .button(.cancel): (SWFKeyCode.tab, 9)
        case .move(.up), .move(.down), .button(.yButton), .button(.leftEquip), .pointer,
             .release, .activate: nil
        }
    }

    /// Sends one sub-menu key straight to the runtime. Returns whether it took the key.
    @discardableResult
    public static func handle(_ event: MenuInputEvent, runtime: SWFMovieRuntime) -> Bool {
        guard let key = key(for: event) else { return false }
        let down = runtime.handle(.keyDown(code: key.code, ascii: key.ascii))
        let up = runtime.handle(.keyUp(code: key.code))
        return down || up
    }

    /// Sends one sub-menu key through the renderer, which repaints the movie.
    @MainActor
    @discardableResult
    public static func send(_ event: MenuInputEvent, renderer: any RendererPort) throws -> Bool {
        guard let key = key(for: event) else { return false }
        let down = try renderer.sendSWFInput(.keyDown(code: key.code, ascii: key.ascii))
        let up = try renderer.sendSWFInput(.keyUp(code: key.code))
        return down || up
    }
}
