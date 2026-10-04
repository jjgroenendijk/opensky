// HUD notifications and help messages through the vanilla movie's own entry
// points on `/HUDMovieBaseInstance`. The parameter shapes were read from the
// installed movie: docs/engine/messages.md#the-hud-movie.

import Foundation
import OpenSkyFormatsSWF

nonisolated extension HUDMovieBridge {
    public static let messageEntryPoints = ["ShowMessage", "ShowTutorialHintText"]

    /// Queues one line in the movie's notification list, which fades it out itself.
    public static func showNotification(_ text: String, runtime: SWFMovieRuntime) {
        runtime.callMovie("ShowMessage", atPath: targetPath, arguments: [.string(text)])
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
    public static func parameterNames(of name: String, runtime: SWFMovieRuntime) -> [String]? {
        guard
            let target = runtime.node(atPath: targetPath, from: runtime.root),
            let function = target.object.lookup(name)?.property.value.functionValue,
            case let .bytecode(body) = function.callable
        else { return nil }
        return body.definition.parameterNames
    }
}
