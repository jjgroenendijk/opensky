import Foundation
@testable import OpenSky
@testable import OpenSkyFormatsSWF
@testable import OpenSkyGameData
@testable import OpenSkyMenus
@testable import OpenSkyRendering
import Testing

enum JournalMovieFixture {
    /// Brings the journal up on its Quests page, the same way the app does.
    @MainActor
    static func open(
        renderer: Renderer,
        fileSystem: VirtualFileSystem
    ) throws -> SWFMovieRuntime {
        let movie = try SWFMovieLoader(fileSystem: fileSystem).load(
            path: QuestJournalMovieBridge.moviePath
        )
        try renderer.setSWFMovie(movie)
        renderer.swfEnabled = true
        renderer.swfScale = 1
        let runtime = try #require(
            try renderer.startSWFRuntime(prepare: SystemMenuMovieBridge.prepare(runtime:))
        )
        try renderer.updateSWFRuntime { runtime in
            SystemMenuMovieBridge.activate(runtime: runtime) {}
            QuestJournalMovieBridge.activate(runtime: runtime)
        }
        for _ in 0 ..< SystemMenuMovieBridge.activationTicks {
            try renderer.advanceSWFRuntime()
        }
        return runtime
    }
}
