// HUD notifications and help messages through the vanilla movie's own entry
// points on `/HUDMovieBaseInstance`. The parameter shapes were read from the
// installed movie: docs/engine/messages.md#the-hud-movie.

import Foundation
public import OpenSkyFormatsSWF
public import OpenSkyMenusInterface

nonisolated extension HUDMovieBridge {
    static let messageEntryPoints = ["ShowMessage", "ShowTutorialHintText"]

    /// Queues one line in the movie's notification list, which fades it out itself.
    public static func showNotification(_ text: String, runtime: SWFMovieRuntime) {
        runtime.callMovie("ShowMessage", atPath: targetPath, arguments: [.string(text)])
    }

    /// The big centred notice through the movie's `ShowNotification` callback: a quest
    /// title over its status, or a learned word under its shout. The movie plays the
    /// sound through its `PlaySound` call.
    public static func showBigNotice(_ notice: HUDBigNotice, runtime: SWFMovieRuntime) {
        let shout = notice.kind == .shout
        runtime.callMovie("ShowNotification", arguments: [
            .string(shout ? "" : notice.title), .string(notice.status), .string(notice.sound ?? ""),
            .integer(0), .integer(shout ? 3 : 0), .integer(0), .integer(0), .integer(0),
            .string(shout ? notice.title : "")
        ])
    }

    /// Shows a help message, or hides it when `text` is nil.
    public static func setHelpMessage(_ text: String?, runtime: SWFMovieRuntime) {
        runtime.callMovie(
            "ShowTutorialHintText",
            atPath: targetPath,
            arguments: [.string(text ?? ""), .boolean(text != nil)]
        )
    }

    /// The parameter names of one movie function, or nil when the movie has none by that name.
    static func parameterNames(of name: String, runtime: SWFMovieRuntime) -> [String]? {
        guard
            let target = runtime.node(atPath: targetPath, from: runtime.root),
            let function = target.object.lookup(name)?.property.value.functionValue,
            case let .bytecode(body) = function.callable
        else { return nil }
        return body.definition.parameterNames
    }
}
