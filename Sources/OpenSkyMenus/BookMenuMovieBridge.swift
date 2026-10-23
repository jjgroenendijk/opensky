// The measured AS2 contract of `Interface\book.swf`. `BookMenu.onLoad` registers
// `SetBookText(text, isNote)`, `TurnPage(delta)`, and `PrepForClose` with GameDelegate.
// The movie lays out the pages itself. See docs/engine/books.md.

import Foundation
import OpenSkyFormatsSWF

nonisolated public enum BookMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\book.swf"

    public static func activate(runtime: SWFMovieRuntime, text: String, isNote: Bool) {
        runtime.registerHostFunction("PlaySound") { _ in .undefined }
        runtime.callMovie("SetBookText", arguments: [.string(text), .boolean(isNote)])
    }

    /// A book turns a spread of two pages; a note turns one.
    public static func turnPage(forward: Bool, isNote: Bool, runtime: SWFMovieRuntime) {
        let step = isNote ? 1 : 2
        runtime.callMovie("TurnPage", arguments: [.integer(forward ? step : -step)])
    }
}
