// How a CSTY scales the combat machine: neutral at the default style, clamped
// at the extremes, and a seeded fight that changes with the style.

@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
import OpenSkyFormatsESM
import Testing

@MainActor
struct CombatStyleTuningTests {
    private static func tuning(
        offense: Float = 0.5,
        defense: Float = 0.5,
        melee: Float = 1,
        magic: Float = 1
    )
        -> CombatStyleTuning
    {
        CombatStyleTuning(
            offensiveMultiplier: offense, defensiveMultiplier: defense,
            meleeScoreMultiplier: melee, magicScoreMultiplier: magic
        )
    }

    @Test func neutralStyleKeepsTheBaseSettings() {
        let base = CombatBehaviorSettings.standard
        let tuned = base.tuned(by: .neutral)
        #expect(tuned.attackIntervalSeconds == base.attackIntervalSeconds)
        #expect(tuned.blockSeconds == base.blockSeconds)
        #expect(tuned.blockChance == base.blockChance)
        #expect(tuned.castChance == base.castChance)
        #expect(base.tuned(by: nil) == base)
    }

    @Test func offenseShortensTheGapWithinItsRange() {
        #expect(Self.tuning(offense: 1).attackIntervalScale() == 0.5)
        #expect(Self.tuning(offense: 0.25).attackIntervalScale() == 2)
        #expect(Self.tuning(offense: 10).attackIntervalScale() == 0.5)
        #expect(Self.tuning(offense: 0.01).attackIntervalScale() == 2)
        #expect(Self.tuning(offense: .nan).attackIntervalScale() == 1)
    }

    @Test func defenseAndMagicScaleTheirChances() {
        #expect(Self.tuning(defense: 1).blockChance(base: 0.3) == 0.6)
        #expect(Self.tuning(defense: 5).blockChance(base: 0.3) == 0.9)
        #expect(Self.tuning(defense: 0).blockChance(base: 0.3) == 0.3)
        #expect(Self.tuning(melee: 0, magic: 1).castChance(base: 0.4) == 0.8)
        #expect(Self.tuning(melee: 1, magic: 0).castChance(base: 0.4) == 0)
        #expect(Self.tuning(melee: 0, magic: 0).castChance(base: 0.4) == 0.4)
    }

    @Test func machineUsesTheActorsStyle() {
        let (runtime, world) = CombatLoopFixture.session()
        world.styles[CombatLoopFixture.opponent] = Self.tuning(offense: 1)
        #expect(runtime.styleTuning(of: CombatLoopFixture.opponent)?.offensiveMultiplier == 1)
        let machine = runtime.makeMachine(for: CombatLoopFixture.opponent)
        #expect(machine.settings.attackIntervalSeconds == runtime.behaviorSettings
            .attackIntervalSeconds * 0.5)
    }

    @Test func aggressiveStyleLandsMoreBlowsInTheSameFight() {
        func damageTaken(_ style: CombatStyleTuning?) -> Float {
            let (runtime, world) = CombatLoopFixture.session()
            world.styles[CombatLoopFixture.opponent] = style
            CombatLoopFixture.engage(runtime, world)
            CombatLoopFixture.run(runtime, seconds: 12)
            return world.damage[.player] ?? 0
        }
        let neutral = damageTaken(nil)
        let aggressive = damageTaken(Self.tuning(offense: 1))
        #expect(neutral > 0)
        #expect(aggressive > neutral)
    }
}
