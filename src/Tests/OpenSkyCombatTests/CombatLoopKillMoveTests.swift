// An NPC whose killing swing starts out of reach closes in, and the kill move is asked
// for once the target is in reach during the wind-up.

@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
import OpenSkyFormatsESM
import simd
import Testing

@MainActor
struct CombatLoopKillMoveTests {
    private typealias Fixture = CombatLoopFixture

    /// Out of reach, but inside the distance a swing may start from with a hold of 3.
    private static let holdFeet = SIMD3<Float>(250, 0, 0)

    private static func spacedSession() -> (CombatLoopRuntime, FakeCombatWorld) {
        let (runtime, world) = Fixture.session()
        var settings = runtime.behaviorSettings
        settings.weaponRangeHoldMult = 3
        runtime.behaviorSettings = settings
        Fixture.engage(runtime, world)
        step(runtime, until: .spacing)
        world.place(Fixture.opponent, at: holdFeet)
        step(runtime, until: .windup)
        return (runtime, world)
    }

    @Test func aSwingThatStartsOutOfReachAsksForTheKillMoveOnceInReach() {
        let (runtime, world) = Self.spacedSession()
        #expect(runtime.phase(of: Fixture.opponent) == .windup)
        #expect(world.killMoveAttempts.isEmpty)
        #expect(runtime.killMoveSeekers[Fixture.opponent] == .player)
        world.playsKillMoves = true
        world.place(Fixture.opponent, at: Fixture.closeFeet)
        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds)
        #expect(world.killMoveAttempts.map(\.actor) == [Fixture.opponent])
        #expect(world.killMoveAttempts.map(\.target) == [.player])
        #expect(runtime.killMoveSeekers.isEmpty)
        #expect(runtime.phase(of: Fixture.opponent) != .windup)
    }

    @Test func aDeclinedKillMoveIsNotAskedForAgain() {
        let (runtime, world) = Self.spacedSession()
        world.place(Fixture.opponent, at: Fixture.closeFeet)
        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 3)
        #expect(world.killMoveAttempts.count == 1)
        #expect(runtime.killMoveSeekers.isEmpty)
    }

    @Test func theSeekingEndsWithTheWindUp() {
        let (runtime, world) = Self.spacedSession()
        Fixture.run(runtime, seconds: CombatBehaviorSettings.standard.windupSeconds + 0.1)
        #expect(world.killMoveAttempts.isEmpty)
        #expect(runtime.killMoveSeekers.isEmpty)
    }

    /// Steps for at most five seconds until the opponent is in `phase`.
    private static func step(_ runtime: CombatLoopRuntime, until phase: CombatBehaviorPhase) {
        for _ in 0 ..< 300 where runtime.phase(of: Fixture.opponent) != phase {
            Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds)
        }
    }
}
