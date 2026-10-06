// The subtitle settings decide which lines show, and a line clears on time.

import OpenSkyGameData
@testable import OpenSkyMenus
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
        let subtitles = SubtitleCoordinator()
        subtitles.attach(presenter: presenter)
        subtitles.settings = SubtitleSettings(dialogue: true, general: false)

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
        let subtitles = SubtitleCoordinator()
        subtitles.attach(presenter: presenter)
        subtitles.settings = SubtitleSettings(dialogue: false, general: true)
        #expect(subtitles.say("Run!", kind: .general, seconds: 5, now: 0))
        subtitles.settings.dialogue = true
        #expect(subtitles.current == "Run!")
        subtitles.settings.general = false
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
}
