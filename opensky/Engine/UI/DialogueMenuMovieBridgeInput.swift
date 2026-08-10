// Renderer-routed input and movie readback for the dialogue menu bridge (issue
// #205). Satellite of UI/DialogueMenuMovieBridge.swift.
//
// `handle(_:runtime:)` mutates the runtime and nothing else, so a caller that
// uses it against a live renderer moves the movie without pushing the
// regenerated command stream to the GPU. That was issue #300 against the system
// menu; this overload exists so the dialogue menu cannot repeat it, because
// `Renderer.sendSWFInput` both delivers the key and repaints.

import Foundation

nonisolated extension DialogueMenuMovieBridge {
    /// Delivers one menu event to a live movie through the renderer, which
    /// synchronizes the drawn command stream with whatever the movie changed.
    ///
    /// - Returns: whether the movie consumed the event.
    @MainActor
    @discardableResult
    static func send(_ event: MenuInputEvent, renderer: Renderer) throws -> Bool {
        guard let key = key(for: event) else { return false }
        let down = try renderer.sendSWFInput(.keyDown(code: key.code, ascii: key.ascii))
        let up = try renderer.sendSWFInput(.keyUp(code: key.code))
        return down || up
    }

    /// Everything a readout wants back out of the live movie, in one pass.
    ///
    /// One value rather than five accessors because the panel samples at 2 Hz
    /// and each read walks the display tree by path; batching them keeps that
    /// to one walk per field instead of one per refresh per caller.
    @MainActor
    static func readback(renderer: Renderer) -> DialogueMenuReadback {
        guard let runtime = renderer.swfRuntime else { return .empty }
        return DialogueMenuReadback(
            rows: topicLabels(runtime: runtime).count,
            selection: selectedIndex(runtime: runtime),
            subtitle: subtitleText(runtime: runtime),
            menuState: menuState(runtime: runtime),
            diagnostics: diagnostics(runtime: runtime)
        )
    }
}

/// What the live movie answers about itself.
nonisolated struct DialogueMenuReadback: Equatable, Sendable {
    let rows: Int
    let selection: Int?
    let subtitle: String?
    let menuState: Int?
    let diagnostics: DialogueMenuDiagnostics

    static let empty = DialogueMenuReadback(
        rows: 0, selection: nil, subtitle: nil, menuState: nil, diagnostics: .none
    )
}
