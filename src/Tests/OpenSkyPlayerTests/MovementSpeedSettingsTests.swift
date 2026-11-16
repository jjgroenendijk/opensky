// The movement speed rules: worn weight slows the gaits, more with a weapon drawn, and
// `SpeedMult` scales the rest.

import OpenSkyEngineTesting
import OpenSkyFormatsTesting
import OpenSkyGameData
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

    @Test func speedMultScalesEveryGaitAndTheWeightOnlyTheRun() {
        let settings = MovementSpeedSettings.vanilla
        // Half the maximum weight, sheathed: 1 - 0.15 x 0.5 = 0.925 of the run.
        let movement = settings.movement(wornWeight: 57.5, weaponDrawn: false, speedMult: 120)
        #expect(movement.multiplier == 1.2)
        #expect(abs(movement.runShare - 0.925) < 0.0001)
        #expect(abs(movement.run(400, walk: 100) - 370) < 0.001)
        // A heavy load never slows a run below the walk.
        #expect(ActorMovementSpeeds(runShare: 0.1).run(400, walk: 100) == 100)
        #expect(ActorMovementSpeeds(canRun: false).run(400, walk: 100) == 100)
        // A SpeedMult of 0 counts as 100, and a negative one counts as its size.
        #expect(ActorMovementSpeeds.multiplier(speedMult: 0) == 1)
        #expect(ActorMovementSpeeds.multiplier(speedMult: -50) == 0.5)
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
