// Renderer-routed input for the inventory menu bridge. Every renderer entry
// point ends by pulling `sceneIfChanged()`, so `Renderer.sendSWFInput` both
// delivers the key and repaints; driving the runtime alone would not update
// the frame.

import Foundation
public import OpenSkyFormatsSWF
public import OpenSkyMenusInterface
public import OpenSkyRendering

@MainActor
extension InventoryMenuMovieBridge {
    /// Delivers one menu event to a live movie through the renderer, which
    /// synchronizes the drawn command stream with whatever the movie changed.
    ///
    /// - Returns: whether the movie consumed the event.
    @discardableResult
    public static func send(_ event: MenuInputEvent, renderer: any RendererPort) throws -> Bool {
        guard let key = key(for: event) else {
            return false
        }
        let down = try renderer.sendSWFInput(.keyDown(code: key.code, ascii: key.ascii))
        let up = try renderer.sendSWFInput(.keyUp(code: key.code))
        return down || up
    }
}

nonisolated extension InventoryMenuMovieBridge {
    /// Whether the item panel is open beside the categories. The menu opens on the
    /// category list alone; the item keys act only once this is true.
    public static func showsItems(runtime: SWFMovieRuntime) -> Bool {
        ItemCardSubMenuBridge.listsState(runtime: runtime) == ItemCardSubMenuBridge.twoPanelsState
    }

    /// Sends one arrow key to the movie, which owns the focus: up and down move the
    /// focused list, right opens the item panel, and left closes it. The model then
    /// takes the category and row the movie selected. False when the movie declined it.
    public static func navigate(
        _ direction: MenuInputEvent.Direction,
        model: inout InventoryMenuModel,
        runtime: SWFMovieRuntime,
        deliver: (MenuInputEvent) throws -> Bool
    ) rethrows -> Bool {
        guard try deliver(.move(direction)) else { return false }
        adoptSelection(into: &model, runtime: runtime)
        return true
    }

    /// A new category refilters the rows, so the movie's row index belongs to the
    /// old rows and is not taken.
    static func adoptSelection(into model: inout InventoryMenuModel, runtime: SWFMovieRuntime) {
        if
            let category = selectedCategoryIndex(runtime: runtime),
            category != model.selectedCategoryIndex
        {
            model.selectCategory(category)
            return
        }
        if let row = selectedIndex(runtime: runtime) {
            model.select(row)
        }
    }
}
