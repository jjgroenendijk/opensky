// MQ101 names the opening titles "Sequence1" to "Sequence4"; `titles.swf` names its clips
// in lower case, and plays one only while the titles are shown.

@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@MainActor
struct TitleSequenceCoordinatorTests {
    @Test func aSequenceNameFindsItsClipWithoutCase() {
        #expect(TitleSequenceClip.path(for: "Sequence1") == "_root.sequence1")
        #expect(TitleSequenceClip.path(for: "SEQUENCE4") == "_root.sequence4")
        #expect(TitleSequenceClip.path(for: "Sequence5") == nil)
        #expect(TitleSequenceClip.path(for: "") == nil)
    }

    @Test func aClipPlaysOnlyWhileTheTitlesAreShown() {
        let titles = TitleSequenceCoordinator(movies: nil) { nil }
        #expect(!titles.start("Sequence1"))
        titles.show(true)
        #expect(titles.isShown)
        #expect(titles.start("Sequence2"))
        #expect(titles.lastSequence == "sequence2")
        #expect(!titles.start("Sequence9"))
        titles.show(false)
        #expect(!titles.isShown)
        #expect(!titles.start("Sequence3"))
    }

    /// The titles tick from the clock; without a loaded movie a tick does nothing.
    @Test func aTickBeforeTheMovieLoadsDoesNothing() {
        let titles = TitleSequenceCoordinator(movies: nil) { nil }
        titles.show(true)
        titles.tick(now: 1)
        titles.tick(now: 2)
        #expect(!titles.isLoaded)
        #expect(titles.isShown)
    }
}
