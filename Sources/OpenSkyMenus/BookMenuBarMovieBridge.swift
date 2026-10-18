// The measured AS2 contract of `Interface\bookmenu.swf`, the button bar drawn over the
// book pages. Its frame script calls `BottomBar.InitExtensions`, which registers
// `ShowTakeButton(show, steal)` with GameDelegate. See docs/engine/books.md#the-button-bar.

import Foundation
import OpenSkyFormatsSWF

nonisolated public enum BookMenuBarMovieBridge: Sendable {
    public static let moviePath = "interface\\bookmenu.swf"

    public static func prepare(runtime: SWFMovieRuntime) {
        runtime.registerHostFunction("PlaySound") { _ in .undefined }
    }

    /// The root `InitExtensions` passes the platform to the bar's buttons.
    public static func activate(runtime: SWFMovieRuntime, take: BookTakeButton) {
        runtime.callMovie(
            "InitExtensions",
            arguments: [.number(SystemMenuMovieBridge.pcPlatform), .boolean(false)]
        )
        runtime.callMovie(
            "ShowTakeButton",
            arguments: [.boolean(take != .hidden), .boolean(take == .steal)]
        )
    }
}

/// The bar's take button: hidden for a carried book, else labelled Take or Steal.
nonisolated public enum BookTakeButton: Equatable, Sendable {
    case hidden
    case take
    case steal
}
