// The journal movie's bottom bar: the date line, the player's level, and the
// progress to the next one. The Quests page shows the date; the Stats and System
// pages show the level meter. See docs/engine/journal.md#quest-page-layout.

import Foundation
public import OpenSkyFormatsSWF

/// Where the bottom bar reads the date and the level.
@MainActor
public protocol JournalBottomBarSource: AnyObject {
    var gameDateText: String? { get }
    var tweenLevel: TweenMenuLevel { get }
}

nonisolated extension SystemMenuMovieBridge {
    public static let bottomBarPath = "\(menuPath)/BottomBar"

    /// `SetPlayerInfo(date, level, percent)`: the answer the bar's `InitBar` asks
    /// for with `RequestPlayerInfo`. The meter takes the progress from 0 to 100.
    public static func showPlayerInfo(
        date: String, level: TweenMenuLevel, runtime: SWFMovieRuntime
    ) {
        let percent = Double(min(max(level.progress, 0), 1)) * 100
        runtime.callMovie(
            "SetPlayerInfo",
            atPath: bottomBarPath,
            arguments: [.string(date), .integer(level.level), .number(percent)]
        )
    }

    /// Fills the bar from `source`, when there is a game to read.
    @MainActor
    public static func showPlayerInfo(
        from source: (any JournalBottomBarSource)?, runtime: SWFMovieRuntime
    ) {
        guard let source, let date = source.gameDateText else { return }
        showPlayerInfo(date: date, level: source.tweenLevel, runtime: runtime)
    }
}
