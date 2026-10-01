// Gameplay subtitles on the vanilla HUD. Measured with `swf action-run`: the
// field is `/HUDMovieBaseInstance/SubtitleTextHolder/textField`, bound to the
// `SubtitleText` variable, so `setText(_:of:)` updates both. The holder's
// HUD-mode flags stay as authored; OpenSky sets its visibility directly.
// Nothing here times a line out; the caller clears it.

import Foundation
import OpenSkyFormatsSWF

nonisolated extension HUDMovieBridge {
    /// The field the line is written into, and the holder whose visibility
    /// decides whether it is drawn.
    public static let subtitleHolderPath = "\(targetPath)/SubtitleTextHolder"
    public static let subtitleTextPath = "\(subtitleHolderPath)/textField"

    /// Shows one line of dialogue, or clears the subtitle when `text` is nil or
    /// empty.
    ///
    /// Clearing hides the holder rather than only blanking the field, because
    /// the holder carries authored art around the text and a blank field inside
    /// a visible holder is an empty box on screen.
    public static func setSubtitleText(_ text: String?, runtime: SWFMovieRuntime) {
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
    public static func clearSubtitleText(runtime: SWFMovieRuntime) {
        setSubtitleText(nil, runtime: runtime)
    }

    /// The line the movie's own field currently holds, which is what proves a
    /// publish reached the movie rather than only the engine model. Nil when
    /// the movie has no such field.
    public static func subtitleText(runtime: SWFMovieRuntime) -> String? {
        guard let field = runtime.node(atPath: subtitleTextPath, from: runtime.root) else {
            return nil
        }
        return runtime.text(of: field)
    }

    /// Whether the holder is currently drawn.
    public static func isSubtitleVisible(runtime: SWFMovieRuntime) -> Bool {
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
