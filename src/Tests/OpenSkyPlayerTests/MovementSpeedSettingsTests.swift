// The movement speed rules: worn weight slows the gaits, more with a weapon drawn, and
// `SpeedMult` scales the rest.

import OpenSkyEngineTesting
import OpenSkyFormatsTesting
import OpenSkyPlayer
import Testing

struct MovementSpeedSettingsTests {
    @Test func fullWeightWithAWeaponDrawnLeavesSeventyPercent() {
        let settings = MovementSpeedSettings.vanilla
        #expect(abs(settings.encumbranceFactor(weight: 115, weaponDrawn: true) - 0.7) < 0.0001)
        #expect(abs(settings.encumbranceFactor(weight: 115, weaponDrawn: false) - 0.85) < 0.0001)
    }

    @Test func weightOverTheMaximumSlowsNoMore() {
        let settings = MovementSpeedSettings.vanilla
        #expect(
            settings.encumbranceFactor(weight: 400, weaponDrawn: true)
                == settings.encumbranceFactor(weight: 115, weaponDrawn: true)
        )
        #expect(settings.encumbranceFactor(weight: 0, weaponDrawn: true) == 1)
    }

    @Test func speedMultScalesAfterTheWeight() {
        let settings = MovementSpeedSettings.vanilla
        // Half the maximum weight, sheathed: 1 - 0.15 x 0.5 = 0.925, then 120 / 100.
        let scale = settings.speedScale(wornWeight: 57.5, weaponDrawn: false, speedMult: 120)
        #expect(abs(scale - 0.925 * 1.2) < 0.0001)
    }

    @Test func anEmptyWeightRangeDoesNotSlow() {
        var settings = MovementSpeedSettings.vanilla
        settings.weightMax = 0
        #expect(settings.encumbranceFactor(weight: 50, weaponDrawn: true) == 1)
    }

    @Test func theInstallSettingsReplaceTheDefaults() throws {
        let store = try GameSettingFixture.store([
            "fMoveEncumEffect": .float(0.5),
            "fActorDefaultTurningSpeed": .float(3)
        ])
        let settings = MovementSpeedSettings.resolve(store: store)
        #expect(settings.encumbranceEffect == 0.5)
        #expect(settings.defaultTurnRate == 3)
        #expect(settings.weightMax == MovementSpeedSettings.vanilla.weightMax)
    }
}
