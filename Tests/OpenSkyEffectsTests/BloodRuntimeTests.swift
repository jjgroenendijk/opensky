// Screen and weapon blood: the splatter count, the cap, the fade, the graphics
// option, and the weapon blood's lifetime and falloff.

@testable import OpenSkyEffects
import OpenSkyRendering
import Testing

@MainActor
struct BloodRuntimeTests {
    @Test
    func theCountGrowsWithDamageAndVariesByTheMargin() {
        let settings = BloodEffectSettings.vanilla
        #expect(ScreenBloodRuntime.count(damage: 0, settings: settings, roll: 0.5) == 2)
        #expect(ScreenBloodRuntime.count(damage: 30, settings: settings, roll: 0.5) == 5)
        #expect(ScreenBloodRuntime.count(damage: 30, settings: settings, roll: 0) == 4)
        #expect(ScreenBloodRuntime.count(damage: 30, settings: settings, roll: 1) == 6)
    }

    @Test
    func splattersStopAtTheMaximumCount() {
        var settings = BloodEffectSettings.vanilla
        settings.maxCount = 3
        var runtime = ScreenBloodRuntime(settings: settings)
        runtime.splatter(damage: 100)
        runtime.splatter(damage: 100)
        #expect(runtime.splatters.count == 3)
        #expect(runtime.splatters.allSatisfy { (0.12 ... 0.18).contains($0.size) })
        #expect(runtime.splatters.allSatisfy { (0.3 ... 1).contains($0.opacity) })
    }

    @Test
    func aSplatterHoldsThenFadesAndGoesAtTheDuration() {
        var runtime = ScreenBloodRuntime()
        #expect(runtime.fade(age: 7) == 1)
        #expect(abs(runtime.fade(age: 14) - 0.5) < 1e-4)
        runtime.splatter(damage: 0)
        #expect(runtime.draws.count == runtime.splatters.count * 2, "each with its flare")
        runtime.advance(20)
        #expect(runtime.splatters.isEmpty)
    }

    @Test
    func theOptionOffPlacesNone() {
        let coordinator = EffectsCoordinator()
        coordinator.screenBloodEnabled = false
        #expect(coordinator.splatterScreen(damage: 50) == 0)
        coordinator.screenBloodEnabled = true
        #expect(coordinator.splatterScreen(damage: 50) > 0)
    }

    @Test
    func weaponBloodStaysThenFadesAndIsGoneBelowTheThreshold() {
        var runtime = WeaponBloodRuntime()
        #expect(runtime.strength(age: 10) == 1)
        #expect(abs(runtime.strength(age: 40) - 0.5) < 1e-4)
        #expect(runtime.strength(age: 66) == 0, "0.067 is below 0.07")
        runtime.bloody(.playerWeapon)
        runtime.advance(30)
        #expect(runtime.membranes.map(\.target) == [.playerWeapon])
        runtime.advance(40)
        #expect(runtime.membranes.isEmpty)
    }
}
