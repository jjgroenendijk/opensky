// Renderer-routed input for the system menu bridge (issue #300). Satellite of
// UI/SystemMenuMovieBridge.swift.
//
// `handle(_:runtime:)` mutates the runtime and nothing else. A live movie must
// instead enter through this overload so the renderer pulls the regenerated
// command stream before the next draw.

import Foundation

nonisolated extension SystemMenuMovieBridge {
    /// Delivers one menu event to a live movie and synchronizes any display-list
    /// mutation to the renderer before returning.
    ///
    /// - Returns: whether the movie consumed the event.
    @MainActor
    @discardableResult
    static func send(_ event: MenuInputEvent, renderer: Renderer) throws -> Bool {
        var consumed = false
        try renderer.updateSWFRuntime { runtime in
            consumed = handle(event, runtime: runtime)
        }
        return consumed
    }
}
