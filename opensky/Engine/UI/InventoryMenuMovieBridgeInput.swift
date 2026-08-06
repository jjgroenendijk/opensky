// Renderer-routed input for the inventory menu bridge (M12.2.2, issue #289).
// Satellite of UI/InventoryMenuMovieBridge.swift.
//
// `handle(_:runtime:)` mutates the runtime and nothing else, so a caller that
// uses it against a live renderer moves the movie's selection without pushing
// the regenerated command stream to the GPU, and the frame does not change
// until some later call happens to synchronize the layer. That is issue #300
// against the system menu. This overload exists so the inventory menu cannot
// repeat it: every renderer entry point ends by pulling `sceneIfChanged()`, so
// routing through `Renderer.sendSWFInput` both delivers the key and repaints.

import Foundation

nonisolated extension InventoryMenuMovieBridge {
    /// Delivers one menu event to a live movie through the renderer, which
    /// synchronizes the drawn command stream with whatever the movie changed.
    ///
    /// - Returns: whether the movie consumed the event.
    @MainActor
    @discardableResult
    static func send(_ event: MenuInputEvent, renderer: Renderer) throws -> Bool {
        guard let key = key(for: event) else {
            return false
        }
        let down = try renderer.sendSWFInput(.keyDown(code: key.code, ascii: key.ascii))
        let up = try renderer.sendSWFInput(.keyUp(code: key.code))
        return down || up
    }
}
