// Gameplay subtitles on the vanilla HUD (issue #205, roadmap item 17.3, scope
// point 6). Satellite of UI/HUDMovieBridge.swift.
//
// The field was located when the HUD came up in M8.4.2 and deliberately left
// hidden: `SubtitleTextHolder` ships with a visible authoring sample in it, and
// `HUDMovieBridge.setAuthoredPlaceholderTextEnabled(false:)` hides the holder
// rather than showing the movie's own placeholder text in normal gameplay. The
// comment there reserved it for this milestone; this file is that milestone.
//
// ## The measured shape
//
// `openskycli swf action-run --movie hudmenu.swf --tree-depth 3` puts one text
// field under the holder:
//
//   /HUDMovieBaseInstance/SubtitleTextHolder          the holder clip
//   /HUDMovieBaseInstance/SubtitleTextHolder/textField  the field itself
//
// and `--dump /HUDMovieBaseInstance` shows `SubtitleText` as a property of the
// HUD instance rather than as a display node, which is the field's bound
// variable name: `SWFMovieRuntime.setText(_:of:)` writes the runtime content
// *and* the binding, so one call keeps the drawn string and the variable the
// movie reads in step.
//
// The holder's own properties (`All`, `StealthMode`, `Swimming`, `HorseMode`,
// `CartMode`, `WarHorseMode`, `Favor`, `MovementDisabled`) are the HUD-mode
// flags that decide when the vanilla HUD shows it. OpenSky drives none of them:
// it has one HUD mode, so the holder's visibility is set directly and the flags
// are left as the movie authored them.
//
// ## What this deliberately does not do
//
// Nothing here times a line out. Precise end-of-line timing arrives with item
// 17.5's playback clock; until then the caller clears on advance and on exit,
// which issue #205 states as the interim rule. A subtitle that stayed up
// because nothing told it to go down would be a bug in the caller, and
// `subtitleText(runtime:)` is here so a test can prove it did not happen.

import Foundation

nonisolated extension HUDMovieBridge {
    /// The field the line is written into, and the holder whose visibility
    /// decides whether it is drawn.
    static let subtitleHolderPath = "\(targetPath)/SubtitleTextHolder"
    static let subtitleTextPath = "\(subtitleHolderPath)/textField"

    /// Shows one line of dialogue, or clears the subtitle when `text` is nil or
    /// empty.
    ///
    /// Clearing hides the holder rather than only blanking the field, because
    /// the holder carries authored art around the text and a blank field inside
    /// a visible holder is an empty box on screen.
    static func setSubtitleText(_ text: String?, runtime: SWFMovieRuntime) {
        let line = text ?? ""
        if let field = runtime.node(atPath: subtitleTextPath, from: runtime.root) {
            runtime.setText(line, of: field)
        } else {
            runtime.runtime.noteMissing(subtitleTextPath)
        }
        setSubtitleVisible(!line.isEmpty, runtime: runtime)
    }

    /// Clears the subtitle. Named rather than folded into a nil argument
    /// because "the line ended" is a different intent from "here is the line",
    /// and the caller reads better for saying which one it means.
    static func clearSubtitleText(runtime: SWFMovieRuntime) {
        setSubtitleText(nil, runtime: runtime)
    }

    /// The line the movie's own field currently holds, which is what proves a
    /// publish reached the movie rather than only the engine model. Nil when
    /// the movie has no such field.
    static func subtitleText(runtime: SWFMovieRuntime) -> String? {
        guard let field = runtime.node(atPath: subtitleTextPath, from: runtime.root) else {
            return nil
        }
        return runtime.text(of: field)
    }

    /// Whether the holder is currently drawn.
    static func isSubtitleVisible(runtime: SWFMovieRuntime) -> Bool {
        runtime.node(atPath: subtitleHolderPath, from: runtime.root)?.isVisible ?? false
    }

    private static func setSubtitleVisible(_ visible: Bool, runtime: SWFMovieRuntime) {
        guard let holder = runtime.node(atPath: subtitleHolderPath, from: runtime.root) else {
            runtime.runtime.noteMissing(subtitleHolderPath)
            return
        }
        runtime.setDisplayProperty(.visible, of: holder, to: .boolean(visible))
    }
}
