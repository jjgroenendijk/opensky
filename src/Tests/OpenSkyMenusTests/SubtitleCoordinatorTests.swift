// The subtitle settings decide which lines show, and a line clears on time.

import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@MainActor
private final class FakeSubtitlePresenter: SubtitlePresenting {
    var shown: [String?] = []

    func presentSubtitle(_ text: String?) {
        shown.append(text)
    }
}

@MainActor
struct SubtitleCoordinatorTests {
    @Test
    func eachSettingGatesItsKindAndALineClearsOnTime() {
        let presenter = FakeSubtitlePresenter()
        let subtitles = SubtitleCoordinator(presenter: presenter)
        subtitles.apply(SubtitleSettings(dialogue: true, general: false))

        #expect(!subtitles.say("Hey, you.", kind: .general, seconds: 2, now: 0))
        #expect(subtitles.say("Hey, you.", kind: .dialogue, seconds: 2, now: 0))
        #expect(subtitles.current == "Hey, you.")
        subtitles.advance(to: 1.9)
        #expect(subtitles.current == "Hey, you.")
        subtitles.advance(to: 2)
        #expect(subtitles.current == nil)
        #expect(presenter.shown == ["Hey, you.", nil])
    }

    @Test
    func turningTheSettingOffHidesTheShownLine() {
        let presenter = FakeSubtitlePresenter()
        let subtitles = SubtitleCoordinator(presenter: presenter)
        subtitles.apply(SubtitleSettings(dialogue: false, general: true))
        #expect(subtitles.say("Run!", kind: .general, seconds: 5, now: 0))
        subtitles.apply(SubtitleSettings(dialogue: true, general: true))
        #expect(subtitles.current == "Run!")
        subtitles.apply(SubtitleSettings(dialogue: true, general: false))
        #expect(subtitles.current == nil)
        #expect(presenter.shown == ["Run!", nil])
        #expect(!subtitles.say("", kind: .dialogue, seconds: 1, now: 0))
    }
}

@MainActor
struct SubtitleSettingsTests {
    @Test
    func theStoreFeedsBothSubtitleSettings() {
        let settings = PlayerSettingsCoordinator(store: PlayerSettingsStore(persistence: nil))
        settings.store.set(.generalSubtitles, to: 1)
        #expect(settings.hud.subtitles == SubtitleSettings(dialogue: false, general: true))
        settings.store.set(.dialogueSubtitles, to: 1)
        #expect(settings.hud.subtitles.shows(.dialogue))
    }

    /// A far speaker shows no subtitle unless its line is forced; a forced or nearer
    /// line keeps its place against a later one.
    @Test
    func distanceAndForceDecideWhichLineShows() {
        let subtitles = SubtitleCoordinator(presenter: FakeSubtitlePresenter())
        subtitles.apply(SubtitleSettings(dialogue: false, general: true))
        let far = SubtitlePlacement(distance: 1300, forced: false)
        #expect(!subtitles.say("Far.", kind: .general, seconds: 5, now: 0, placement: far))
        let forced = SubtitlePlacement(distance: 1300, forced: true)
        #expect(subtitles.say("Forced.", kind: .general, seconds: 5, now: 0, placement: forced))
        let near = SubtitlePlacement(distance: 100, forced: false)
        #expect(!subtitles.say("Near.", kind: .general, seconds: 5, now: 1, placement: near))
        #expect(subtitles.say("Later.", kind: .general, seconds: 5, now: 6, placement: near))
        let nearer = SubtitlePlacement(distance: 50, forced: false)
        #expect(subtitles.say("Nearer.", kind: .general, seconds: 5, now: 7, placement: nearer))
        #expect(subtitles.current == "Nearer.")
    }
}
