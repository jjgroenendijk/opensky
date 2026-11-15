// The measured AS2 contract of `Interface\tweenmenu.swf`. The movie owns the four
// entries, their highlight, and the open and close animations. It calls the engine with
// `HighlightMenu`, `OpenHighlightedMenu`, `StartCloseMenu`, and `CloseMenu`. See
// docs/engine/tween-menu.md.

import Foundation
public import OpenSkyFormatsSWF
public import OpenSkyMenusInterface

/// A call the Tween movie makes.
nonisolated public enum TweenMovieEvent: Equatable, Sendable {
    case highlight(TweenMenuChoice)
    case open(TweenMenuChoice)
    /// The movie started its close animation itself, on the Tab key.
    case closing
    /// The close animation ended.
    case closed
}

/// What the bottom bar shows when the menu opens.
nonisolated public struct TweenMenuContent: Equatable, Sendable {
    public var date: String
    public var level: Int
    /// Experience toward the next level, 0 to 1.
    public var levelProgress: Float
    /// A level waits, so the Skills entry reads "LEVEL UP".
    public var levelUpReady: Bool

    public init(date: String, level: Int, levelProgress: Float, levelUpReady: Bool) {
        self.date = date
        self.level = level
        self.levelProgress = levelProgress
        self.levelUpReady = levelUpReady
    }
}

nonisolated public enum TweenMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\tweenmenu.swf"
    public static let sinkHostFunctions = ["PlaySound", "myLog", "OpenAnimFinished"]

    public static func prepare(
        runtime: SWFMovieRuntime,
        onEvent: @escaping @MainActor @Sendable (TweenMovieEvent) -> Void
    ) {
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        runtime.registerHostFunction("HighlightMenu") { call in
            if let choice = choice(call.arguments.first) {
                MainActor.assumeIsolated { onEvent(.highlight(choice)) }
            }
            return .undefined
        }
        runtime.registerHostFunction("OpenHighlightedMenu") { call in
            if let choice = choice(call.arguments.first) {
                MainActor.assumeIsolated { onEvent(.open(choice)) }
            }
            return .undefined
        }
        runtime.registerHostFunction("StartCloseMenu") { _ in
            MainActor.assumeIsolated { onEvent(.closing) }
            return .undefined
        }
        runtime.registerHostFunction("CloseMenu") { _ in
            MainActor.assumeIsolated { onEvent(.closed) }
            return .undefined
        }
    }

    /// The root `InitExtensions` wires the entries; `StartOpenMenuAnim` fills the bar
    /// and plays the open animation.
    public static func activate(runtime: SWFMovieRuntime, content: TweenMenuContent) {
        runtime.callMovie("InitExtensions")
        runtime.callMovie("ShowMenu")
        runtime.callMovie("StartOpenMenuAnim", arguments: [
            .boolean(content.levelUpReady), .string(content.date),
            .string(String(content.level)),
            .number(Double(min(max(content.levelProgress, 0), 1)) * 100)
        ])
    }

    /// Plays the close animation; the movie calls `CloseMenu` at its end.
    public static func startClose(runtime: SWFMovieRuntime) {
        runtime.callMovie("StartCloseMenuAnim")
    }

    static func choice(_ value: AS2Value?) -> TweenMenuChoice? {
        guard case let .number(number)? = value, number.isFinite else { return nil }
        return TweenMenuChoice(rawValue: Int(number))
    }
}
