// Renderer-routed input for the inventory menu bridge. Every renderer entry
// point ends by pulling `sceneIfChanged()`, so `Renderer.sendSWFInput` both
// delivers the key and repaints; driving the runtime alone would not update
// the frame.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyRendering

nonisolated extension InventoryMenuMovieBridge {
    /// Delivers one menu event to a live movie through the renderer, which
    /// synchronizes the drawn command stream with whatever the movie changed.
    ///
    /// - Returns: whether the movie consumed the event.
    @MainActor
    @discardableResult
    public static func send(_ event: MenuInputEvent, renderer: Renderer) throws -> Bool {
        guard let key = key(for: event) else {
            return false
        }
        let down = try renderer.sendSWFInput(.keyDown(code: key.code, ascii: key.ascii))
        let up = try renderer.sendSWFInput(.keyUp(code: key.code))
        return down || up
    }
}
