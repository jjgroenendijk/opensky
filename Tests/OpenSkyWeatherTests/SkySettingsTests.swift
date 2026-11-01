// The sky GMSTs, the accelerated weather fade, and the celestial sky of the current
// climate. Synthetic fixtures only.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyRenderCore
@testable import OpenSkyWeather
import Testing

struct SkySettingsTests {
    @Test func settingsComeFromTheStoreAndKeepTheFallbackOtherwise() throws {
        let file = try GameSettingFixture.plugin(settings: [
            "iMasserSize": .integer(120),
            "fAutoraFadeIn": .float(21),
            "fStarsRotateYAxis": .float(0.5),
            "fWeatherTransAccel": .float(8)
        ])
        let settings = SkySettings.resolve(store: GameSettingStore(plugins: [("Sky.esp", file)]))
        #expect(settings.masser.size == 120)
        #expect(settings.auroraFadeIn == 21)
        #expect(settings.starsRotateAxis.y == 0.5)
        #expect(settings.weatherTransAccel == 8)
        #expect(settings.secunda.size == SkySettings.vanilla.secunda.size)
        #expect(settings.sunXExtreme == 400)
    }

    @Test func anAcceleratedFadeRunsFWeatherTransAccelTimesFaster() throws {
        let system = try WeatherSystem(store: WeatherRuntimeTests.store(), worldspaceFormID: 0x500)
        system.forceWeather(FormID(0x100), transition: .instant)
        // Weather 0x200 fades over 0.25 game hours; sixteen times faster is 1/64 of an hour.
        system.forceWeather(FormID(0x200), transition: .accelerated)
        system.update(hour: 12, elapsedGameHours: 0.25 / 32)
        #expect(abs(system.transitionFraction - 0.5) < 1e-3)
    }

    @Test func theCelestialSkyReadsTheWorldspaceClimate() throws {
        let system = try WeatherSystem(
            store: WeatherRuntimeTests.store(volatility: 50), worldspaceFormID: 0x500
        )
        let sky = system.celestialSky(hour: 0, daysPassed: 0, settings: .vanilla)
        // The fixture climate's moons byte is 3: a 3-day phase and neither moon.
        #expect(system.climate?.timing?.phaseLengthDays == 3)
        #expect(sky.moons.isEmpty)
        #expect(sky.sunAlpha == 0)
    }
}
