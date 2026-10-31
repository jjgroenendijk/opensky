// The measured AS2 contract of `Interface\loadingmenu.swf`, the loading screen's
// tip and level meter. `/Menu_mc.FadeInMenu` asks `RequestLoadingText`, whose answer
// goes to `SetLoadingText`; `SetLevelProgress(level, percent, show)` fills the meter.
// See docs/engine/loading-screens.md#the-loading-movie.

import Foundation
import OpenSkyFormatsSWF

/// What the loading movie shows: the tip and the player's level.
nonisolated public struct LoadingMenuContent: Equatable, Sendable {
    public var text: String
    public var level: Int
    /// Experience toward the next level, 0 to 1.
    public var levelProgress: Float

    public init(text: String, level: Int, levelProgress: Float) {
        self.text = text
        self.level = level
        self.levelProgress = levelProgress
    }
}

nonisolated public enum LoadingMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\loadingmenu.swf"
    public static let menuPath = "/Menu_mc"

    /// `text` answers the movie's own tip requests; the movie asks again after a fade.
    public static func prepare(
        runtime: SWFMovieRuntime,
        text: @escaping @MainActor @Sendable () -> String
    ) {
        for name in ["PlaySound", "myLog", "RequestPlayerInfo"] {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        runtime.registerHostFunction("RequestLoadingText") { _ in
            .string(MainActor.assumeIsolated { text() })
        }
    }

    /// `InitExtensions` locks the meter and the tip to the stage corners.
    public static func activate(runtime: SWFMovieRuntime, content: LoadingMenuContent) {
        runtime.callMovie("InitExtensions")
        runtime.callMovie(
            "SetPlatform",
            arguments: [.number(SystemMenuMovieBridge.pcPlatform), .boolean(false)]
        )
        runtime.callMovie("FadeInMenu", atPath: menuPath)
        publish(content, runtime: runtime)
    }

    public static func publish(_ content: LoadingMenuContent, runtime: SWFMovieRuntime) {
        runtime.callMovie("SetLoadingText", atPath: menuPath, arguments: [.string(content.text)])
        runtime.callMovie("SetLevelProgress", atPath: menuPath, arguments: [
            .number(Double(content.level)),
            .number(Double(min(max(content.levelProgress, 0), 1)) * 100),
            .boolean(true)
        ])
    }

    public static func fadeOut(runtime: SWFMovieRuntime) {
        runtime.callMovie("FadeOutMenu", atPath: menuPath)
    }
}
