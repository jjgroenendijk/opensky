// MQ101 names the opening titles "Sequence1" to "Sequence4"; `titles.swf` names its clips
// in lower case, and plays one only while the titles are shown.

@testable import OpenSkyMenus
import Testing

@MainActor
struct TitleSequenceCoordinatorTests {
    @Test func aSequenceNameFindsItsClipWithoutCase() {
        #expect(TitleSequenceMovieBridge.clipPath(for: "Sequence1") == "_root.sequence1")
        #expect(TitleSequenceMovieBridge.clipPath(for: "SEQUENCE4") == "_root.sequence4")
        #expect(TitleSequenceMovieBridge.clipPath(for: "Sequence5") == nil)
        #expect(TitleSequenceMovieBridge.clipPath(for: "") == nil)
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
}
