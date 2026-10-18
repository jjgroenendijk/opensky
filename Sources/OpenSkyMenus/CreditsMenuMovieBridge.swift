// The measured AS2 contract of `Interface\creditsmenu.swf`. The movie makes
// `_root.CodeObj` itself; the engine fills it with `requestCredits(field)`,
// `getScrollSpeed()`, and `closeMenu()`, then calls `onCodeObjectInit`.
// See docs/engine/main-menu.md#credits.

import Foundation
import OpenSkyFormatsSWF

nonisolated public enum CreditsMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\creditsmenu.swf"
    /// The credits text in the interface archive.
    public static let creditsPath = "interface\\credits.txt"
    public static let codeObjectName = "CodeObj"
    /// Movie pixels the text moves up per frame. OpenSky's pace: the game reads
    /// its own from code, which is not public.
    public static let scrollSpeed = 1.0

    /// Fills `CodeObj` and starts the scroll. `onClose` runs when the text has
    /// scrolled past or the player leaves.
    public static func activate(
        runtime: SWFMovieRuntime,
        credits: String,
        onClose: @escaping @MainActor @Sendable () -> Void
    ) {
        runtime.registerHostFunction("PlaySound") { _ in .undefined }
        let codeObject: AS2Object
        if let existing = runtime.root.object.lookup(codeObjectName)?.property.value.objectValue {
            codeObject = existing
        } else {
            codeObject = runtime.runtime.makeObject()
            runtime.root.object.define(.object(codeObject), for: codeObjectName)
        }
        let text = SWFEditText.stripHTML(credits)
        AS2Natives.method(runtime.runtime, on: codeObject, name: "requestCredits") {
            [weak runtime] context in
            if let field = SWFDisplayObject.resolve(context.arguments.first?.objectValue) {
                runtime?.setText(text, of: field)
            }
            return .undefined
        }
        AS2Natives.method(runtime.runtime, on: codeObject, name: "getScrollSpeed") { _ in
            .number(scrollSpeed)
        }
        AS2Natives.method(runtime.runtime, on: codeObject, name: "closeMenu") { _ in
            MainActor.assumeIsolated { onClose() }
            return .undefined
        }
        runtime.callMovie(
            "SetPlatform", arguments: [.number(SystemMenuMovieBridge.pcPlatform), .boolean(false)]
        )
        runtime.callMovie("onCodeObjectInit")
    }
}
