// The title menu settings: the credits speed, the version text, and the New question.

import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyMenus
import Testing

struct TitleMenuSettingsTests {
    @Test func theVersionEndsWithTheUpdateNumber() {
        #expect(TitleMenuSettings.vanilla.versionText == "OpenSky.8")
    }

    @Test func theInstallSettingsReplaceTheDefaults() throws {
        let store = try GameSettingFixture.store([
            "fCreditsScrollSpeed": .float(3),
            "iUpdateESMVersion": .integer(9)
        ])
        let settings = TitleMenuSettings.resolve(store: store)
        #expect(settings.creditsScrollSpeed == 3)
        #expect(settings.versionText == "OpenSky.9")
    }

    @Test func theNewQuestionComesFromTheInstall() throws {
        let store = try GameSettingFixture.store(["sConfirmNew": .text("Begin anew?")])
        let settings = TitleMenuSettings.resolve(store: store) { text in
            guard case let .inline(value) = text.text else { return nil }
            return value
        }
        #expect(settings.confirmNewText == "Begin anew?")
        #expect(TitleMenuSettings.vanilla.confirmNewText == "Start a new game?")
    }
}
