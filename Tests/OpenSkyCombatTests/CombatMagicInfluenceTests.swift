// What magic effects force on one actor's combat mind: fear makes it run, Rally
// keeps it in the fight. The rules are the Creation Kit wiki's Demoralize and
// Rally archetypes, cited at `ActorMagicInfluence`.

@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
@testable import OpenSkyMagicInterface
@testable import OpenSkyPerceptionInterface
import Testing

@MainActor
struct CombatMagicInfluenceTests {
    private typealias Fixture = CombatBehaviorFixture

    private static let afraid = ActorMagicInfluence(isFrightened: true)

    @Test func aFrightenedActorFleesAtFullHealth() {
        var inputs = Fixture.inputs()
        inputs.influence = Self.afraid
        #expect(inputs.shouldFlee(settings: Fixture.settings))
    }

    @Test func aRalliedActorDoesNotFleeWhenHurt() {
        var inputs = Fixture.inputs(healthFraction: 0.01)
        inputs.influence = ActorMagicInfluence(isFrightened: true, isRallied: true)
        #expect(!inputs.shouldFlee(settings: Fixture.settings))
    }

    /// "Allies affected by Demoralize prior to combat will not flee until combat
    /// begins": the actor waits unseen, then runs once it perceives the target.
    @Test func aFrightenedActorRunsWhenTheFightBegins() {
        var machine = Fixture.machine()
        var unseen = Fixture.inputs(state: .unaware)
        unseen.influence = Self.afraid
        _ = machine.step(seconds: Fixture.step, inputs: unseen)
        #expect(machine.phase == .idle)

        var seen = Fixture.inputs()
        seen.influence = Self.afraid
        let step = machine.step(seconds: Fixture.step, inputs: seen)
        #expect(step.phase == .fleeing)
    }

    // MARK: - The loop

    /// Calm "lowers the Aggression ... to minimum": a fighting actor stops and
    /// holds still.
    @Test func aCalmedActorLeavesTheFight() {
        let (runtime, world) = CombatLoopFixture.session()
        CombatLoopFixture.engage(runtime, world)
        CombatLoopFixture.run(runtime, seconds: 1)
        #expect(runtime.state.isPlayerInCombat)

        world.influences[CombatLoopFixture.opponent] = ActorMagicInfluence(isCalmed: true)
        CombatLoopFixture.run(runtime, seconds: 1)
        #expect(runtime.phase(of: CombatLoopFixture.opponent) == .idle)
        #expect(world.stopRequests.contains(CombatLoopFixture.opponent))
    }

    @Test func aParalysedActorDealsNoBlows() {
        let (runtime, world) = CombatLoopFixture.session()
        CombatLoopFixture.engage(runtime, world)
        world.influences[CombatLoopFixture.opponent] = ActorMagicInfluence(isParalysed: true)
        CombatLoopFixture.run(runtime, seconds: CombatLoopFixture.cycleSeconds * 3)
        #expect(world.damage.isEmpty)
    }

    /// Frenzy "maxes the Aggression": a neutral actor that sees the player attacks.
    @Test func aFrenziedNeutralActorFights() {
        let (runtime, world) = CombatLoopFixture.session()
        world.awareness[CombatLoopFixture.opponent] = .detected(at: world.player.feet)
        world.influences[CombatLoopFixture.opponent] = ActorMagicInfluence(isFrenzied: true)
        CombatLoopFixture.run(runtime, seconds: 1)
        #expect(runtime.state.isPlayerInCombat)
    }
}
