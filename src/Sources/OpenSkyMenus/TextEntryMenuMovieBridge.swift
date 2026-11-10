// The measured AS2 contract of `Interface\textentry.swf`. The movie only exports the
// `TextEntryClip` symbol, so the engine attaches it, wires its buttons, and listens for
// the `nameChange` event. See docs/engine/text-entry.md.

import Foundation
import OpenSkyFormatsSWF

nonisolated enum TextEntryMenuMovieBridge: Sendable {
    static let moviePath = "interface\\textentry.swf"
    static let linkage = "TextEntryClip"
    static let clipName = "TextEntry_mc"
    static let clipPath = "/\(clipName)"
    /// `TextField_txt` names this child, a CLIK `TextInput`.
    static let inputPath = "\(clipPath)/TextInputInstance"
    static let listenerMethod = "onNameChange"

    /// Attaches the field and listens for its result: true for accept, false for cancel.
    static func activate(
        runtime: SWFMovieRuntime,
        onResult: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        guard
            let clip = runtime.attach(
                linkage: linkage, into: runtime.root, depth: 1, name: clipName
            )
        else { return }
        runtime.callMovie("SetupButtons", atPath: clipPath)
        runtime.callMovie(
            "SetPlatform", atPath: clipPath,
            arguments: [.number(SystemMenuMovieBridge.pcPlatform), .boolean(false)]
        )
        listen(on: clip.object, runtime: runtime, onResult: onResult)
    }

    /// `EventDispatcher` calls `scope[callBack](event)`, so a plain object with one
    /// native method is the listener.
    static func listen(
        on clip: AS2Object, runtime: SWFMovieRuntime,
        onResult: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        guard let add = clip.lookup("addEventListener")?.property.value.functionValue else {
            return
        }
        let listener = runtime.runtime.makeObject()
        AS2Runtime.method(runtime.runtime, on: listener, name: listenerMethod) { context in
            let event = context.argument(0).objectValue
            let accepted = event?.lookup("nameChanged")?.property.value == .boolean(true)
            MainActor.assumeIsolated { onResult(accepted) }
            return .undefined
        }
        AS2Interpreter.invoke(
            in: runtime.runtime,
            .object(add),
            thisValue: .object(clip),
            arguments: [
                .string("nameChange"),
                .object(listener),
                .string(listenerMethod)
            ]
        )
    }

    static func publish(text: String, runtime: SWFMovieRuntime) {
        MenuMovieText.assign(.string(text), member: "text", atPath: inputPath, runtime: runtime)
    }

    /// The buttons' own handlers, so the movie's rule that an empty name is refused holds.
    static func press(accept: Bool, runtime: SWFMovieRuntime) {
        runtime.callMovie(accept ? "onAccept" : "onCancel", atPath: clipPath)
    }
}
