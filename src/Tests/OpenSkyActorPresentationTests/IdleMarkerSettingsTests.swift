// The idle marker settings: the arrival radius and the pause between idles.

import OpenSkyActorPresentation
import OpenSkyEngineTesting
import OpenSkyFormatsTesting
import OpenSkyGameData
import Testing

struct IdleMarkerSettingsTests {
    @Test func theInstallSettingsReplaceTheDefaults() throws {
        #expect(IdleMarkerSettings.vanilla.arrivalRadius == 50)
        let store = try GameSettingFixture.store([
            "fAIMarkerDestinationRadius": .float(80),
            "fAIIdleWaitTime": .float(2)
        ])
        let settings = IdleMarkerSettings.resolve(store: store)
        #expect(settings.arrivalRadius == 80)
        #expect(settings.idleWait == 2)
    }
}
