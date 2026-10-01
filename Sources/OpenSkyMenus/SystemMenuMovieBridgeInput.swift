// Renderer-routed input for the system menu bridge. `handle(_:runtime:)` only
// mutates the runtime; a live movie enters here so the renderer pulls the new
// command stream before the next draw.

import Foundation
import OpenSkyRendering

nonisolated extension SystemMenuMovieBridge {
    /// Delivers one menu event to a live movie and synchronizes any display-list
    /// mutation to the renderer before returning.
    ///
    /// - Returns: whether the movie consumed the event.
    @MainActor
    @discardableResult
    public static func send(_ event: MenuInputEvent, renderer: Renderer) throws -> Bool {
        var consumed = false
        try renderer.updateSWFRuntime { runtime in
            consumed = handle(event, runtime: runtime)
        }
        return consumed
    }
}
