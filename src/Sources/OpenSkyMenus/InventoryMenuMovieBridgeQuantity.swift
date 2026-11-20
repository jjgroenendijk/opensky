// The drop half of the inventory movie. The engine calls the movie's `DropItem`
// callback; the movie opens `ItemCard.ShowQuantityMenu` for a stack above
// `QUANTITY_MENU_COUNT_LIMIT` and answers with `ItemDrop(amount)`.
// See docs/engine/inventory-menu.md#quantity.

import Foundation
public import OpenSkyFormatsSWF

nonisolated extension InventoryMenuMovieBridge {
    /// The engine-to-movie callback `InventoryMenu.InitExtensions` registers for
    /// the drop key.
    public static let dropCallback = "DropItem"

    /// Asks the movie to drop the selected row. Returns false when the movie has
    /// no `DropItem` callback, so the engine drops through its own prompt.
    @discardableResult
    public static func requestDrop(runtime: SWFMovieRuntime) -> Bool {
        guard runtime.movieCallbackNames.contains(dropCallback) else { return false }
        runtime.callMovie(dropCallback)
        return true
    }
}
