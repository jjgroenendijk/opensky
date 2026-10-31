// Renderer-routed input and movie readback for the dialogue menu bridge.
// `Renderer.sendSWFInput` both delivers the key and repaints; driving the
// runtime alone would move the movie without updating the GPU commands.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyRendering

@MainActor
extension DialogueMenuMovieBridge {
    /// Delivers one menu event to a live movie through the renderer, which
    /// synchronizes the drawn command stream with whatever the movie changed.
    ///
    /// - Returns: whether the movie consumed the event.
    @discardableResult
    public static func send(_ event: MenuInputEvent, renderer: Renderer) throws -> Bool {
        guard let key = key(for: event) else { return false }
        let down = try renderer.sendSWFInput(.keyDown(code: key.code, ascii: key.ascii))
        let up = try renderer.sendSWFInput(.keyUp(code: key.code))
        return down || up
    }
}
