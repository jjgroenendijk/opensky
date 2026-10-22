// The sandbox procedure: activity lengths from the game settings, timers on the game
// clock, and meals at the meal times.

@testable import OpenSkyAIPackages
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyWorldInterface
import Testing

struct SandboxProcedureTests {
    private static func machine(
        settings: SandboxSettings = .vanilla, eats: Bool = false, start: SIMD3<Float> = .zero
    ) -> PackageProcedureMachine {
        var setup = PackageProcedureSetup(kind: .sandbox, center: .zero, radius: 500)
        var sandbox = PackageSandboxSetup(settings: settings, start: start)
        sandbox.eats = eats
        setup.sandbox = sandbox
        setup.seed = 7
        return PackageProcedureMachine(setup: setup)
    }

    @Test func anActivityLastsTheBaseTimesItsKindAndEnergy() {
        let settings = SandboxSettings.vanilla
        // 0.2 x 1.5 x (1 + 50 x 0.05 x -0.05) = 0.2625 game hours.
        #expect(abs(settings.baseDuration(of: .idleMarker, energy: 50) - 0.2625) < 0.0001)
        #expect(abs(settings.baseDuration(of: .furniture, energy: 0) - 0.6) < 0.0001)
        let low = settings.duration(of: .idleMarker, energy: 50, unit: 0)
        let high = settings.duration(of: .idleMarker, energy: 50, unit: 1)
        #expect(abs(low - 0.2625 * 0.75) < 0.0001)
        #expect(abs(high - 0.2625 * 1.25) < 0.0001)
    }

    @Test func thePluginSettingsReplaceTheDefaults() throws {
        let file = try GameSettingFixture.plugin(settings: [
            "fSandboxDurationBase": .float(1),
            "fSandboxDurationMultIdleMarker": .float(2),
            "fSandboxEnergyMultIdleMarker": .float(0),
            "fSandboxLunchMin": .float(13),
            "fSandboxMealDurationMax": .float(0.5),
            "fSandboxCylinderBottom": .float(-40),
            "fSandBoxRadiusHysteresis": .float(10)
        ])
        let settings = SandboxSettings.resolve(store: GameSettingStore(plugins: [("S.esp", file)]))
        #expect(settings.baseDuration(of: .idleMarker, energy: 50) == 2)
        #expect(settings.meals[1].earliest == 13)
        #expect(settings.mealDuration == 0.1 ... 0.5)
        #expect(settings.cylinderBottom == -40)
        #expect(settings.radiusHysteresis == 10)
    }

    @Test func anActorOutsideTheAreaWalksInFirst() {
        var outside = Self.machine(start: SIMD3(2000, 0, 0))
        #expect(outside.start().count == 1)
        #expect(outside.state == .moving)
        var inside = Self.machine(start: SIMD3(540, 0, 0))
        #expect(inside.start().isEmpty)
        #expect(inside.state == .sandboxing(.wandering))
        var below = Self.machine(start: SIMD3(0, 0, -200))
        _ = below.start()
        #expect(below.state == .moving)
    }

    @Test func theActivityEndsWhenItsGameHoursRunOut() {
        var machine = Self.machine(start: SIMD3(5000, 0, 0))
        _ = machine.start()
        #expect(machine.handle(.arrivedAtIdleMarker).isEmpty)
        #expect(machine.state == .sandboxing(.idleMarker))
        let hours = machine.sandbox.hoursLeft
        #expect(hours > 0.2625 * 0.74 && hours < 0.2625 * 1.26)
        #expect(machine.handle(.clock(hours: 10)).isEmpty)
        #expect(machine.handle(.tick(600)).isEmpty)
        #expect(machine.handle(.clock(hours: 10 + Double(hours) / 2)).isEmpty)
        let commands = machine.handle(.clock(hours: 10 + Double(hours) + 0.01))
        #expect(commands.first == .endActivity(.idleMarker))
        #expect(machine.state == .moving)
    }

    @Test func aMarkerGivenWhileWanderingStartsAnIdleMarkerActivity() {
        var machine = Self.machine()
        _ = machine.start()
        #expect(machine.state == .sandboxing(.wandering))
        #expect(machine.handle(.arrivedAtIdleMarker).isEmpty)
        #expect(machine.state == .sandboxing(.idleMarker))
        #expect(machine.sandbox.hoursLeft > 0.2625 * 0.74)
    }

    @Test func aDueMealCutsTheActivityShort() {
        var settings = SandboxSettings.vanilla
        settings.meals = [SandboxMealWindow(earliest: 12, latest: 12)]
        settings.mealDuration = 0.5 ... 0.5
        var machine = Self.machine(settings: settings, eats: true)
        _ = machine.start()
        #expect(machine.handle(.clock(hours: 24 + 11.9)).isEmpty)
        #expect(machine.state == .sandboxing(.wandering))
        let commands = machine.handle(.clock(hours: 24 + 12.1))
        #expect(commands == [.endActivity(.wandering), .playLoop(.eat)])
        #expect(machine.state == .sandboxing(.eatStanding))
        #expect(machine.sandbox.meals == [SandboxMeal(start: 36, end: 36.5)])
    }

    @Test func anActorThatMayNotEatSkipsTheMeal() {
        var settings = SandboxSettings.vanilla
        settings.meals = [SandboxMealWindow(earliest: 12, latest: 12)]
        var machine = Self.machine(settings: settings)
        _ = machine.start()
        _ = machine.handle(.clock(hours: 12.05))
        #expect(machine.state == .sandboxing(.wandering))
    }
}
