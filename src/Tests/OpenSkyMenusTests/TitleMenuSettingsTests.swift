// The title menu settings: the credits speed and the version text.

import OpenSkyEngineTesting
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
}
