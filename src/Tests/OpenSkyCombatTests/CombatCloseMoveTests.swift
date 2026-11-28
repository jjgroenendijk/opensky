// The back off, circle, and fall back moves of a melee actor in reach.

@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
import OpenSkyConditions
import simd
import Testing

@MainActor
struct CombatCloseMoveTests {
    private typealias Fixture = CombatBehaviorFixture
    private typealias Loop = CombatCloseMoveLoop

    private static func rules(
        circle: Float = 0, fallback: Float = 0, backOff: Float = 0, backOffDistance: Float = 100
    ) -> Loop.Rules {
        var settings = CombatCloseRangeSettings()
        settings.circleChance = circle
        settings.fallbackChance = fallback
        settings.backOffChance = backOff
        return Loop.Rules(settings: settings, backOffDistance: backOffDistance)
    }

    private static func point(_ command: CombatMovementCommand?) -> SIMD3<Float>? {
        guard case let .reposition(point)? = command else { return nil }
        return point
    }

    @Test func theStyleValuesLerpBetweenTheGameSettings() {
        let settings = CombatCloseRangeRanges().settings(circle: 0.2, fallback: 0.2)
        #expect(abs(settings.circleChance - 0.15) < 0.0001)
        #expect(abs(settings.fallbackChance - 0.1) < 0.0001)
        #expect(abs(settings.fallbackDistance - 128) < 0.0001)
        #expect(abs(settings.fallbackWaitSeconds - 0.9) < 0.0001)
        #expect(abs(settings.circleAngleMax - 42) < 0.0001)
        #expect(CombatSettingRange(0, 1).lerp(.nan) == 0)
        let tuned = CombatBehaviorSettings.standard.tuned(by: .neutral)
        #expect(tuned.closeRange == settings)
        #expect(CombatBehaviorSettings.standard.closeRange == nil)
    }

    @Test func aBackOffWalksOutToTheBackOffDistanceAndEndsThere() throws {
        var loop = Loop()
        var random = ConditionRandom(seed: 1)
        let rules = Self.rules(backOff: 1)
        let near = Fixture.inputs(distance: 50)
        let issued1 = loop.advance(
            now: 0, inputs: near, rules: rules, random: &random
        )
        let target = try #require(Self.point(issued1))
        #expect(simd_distance(target, SIMD3(100, 0, 0)) < 0.001)
        #expect(loop.move?.kind == .backOff)
        #expect(loop.startedCount == 1)
        let waiting = loop.advance(now: 0.05, inputs: near, rules: rules, random: &random)
        #expect(waiting == nil)
        let there = loop.advance(
            now: 0.2, inputs: Fixture.inputs(distance: 100), rules: rules, random: &random
        )
        #expect(there == .hold)
        #expect(loop.move == nil)
    }

    @Test func noMoveStartsWhileTheTargetWalksAwayOrTheActorLooksAway() {
        let rules = Self.rules(circle: 1, fallback: 1, backOff: 1)
        var random = ConditionRandom(seed: 2)
        var away = Fixture.inputs(distance: 50)
        away.targetVelocity = SIMD3(-100, 0, 0)
        var loop = Loop()
        let fled = loop.advance(now: 0, inputs: away, rules: rules, random: &random)
        #expect(fled == nil)
        #expect(loop.nextPass == 0.25)
        var turned = Fixture.inputs(distance: 50)
        turned.facingError = .pi / 2
        loop = Loop()
        let looked = loop.advance(now: 0, inputs: turned, rules: rules, random: &random)
        #expect(looked == nil)
        #expect(Loop.movesAway(Fixture.inputs(distance: 0)) == false)
    }

    @Test func aCircleTurnsAboutTheTargetAndTriesTheOtherSideOnce() throws {
        var loop = Loop()
        var random = ConditionRandom(seed: 3)
        let rules = Self.rules(circle: 1)
        let inputs = Fixture.inputs(distance: 200)
        let issued2 = loop.advance(
            now: 0, inputs: inputs, rules: rules, random: &random
        )
        let first = try #require(Self.point(issued2))
        let angle = abs(atan2(first.y, first.x)) * 180 / .pi
        #expect(abs(simd_length(SIMD2(first.x, first.y)) - 200) < 0.01)
        #expect(angle >= 30 - 0.01 && angle <= 42 + 0.01)
        let other = loop.refused(now: 0)
        let second = try #require(Self.point(other))
        #expect(abs(second.y + first.y) < 0.01)
        let none = loop.refused(now: 0)
        #expect(none == nil)
        #expect(loop.move == nil)
        let ahead = loop.advance(now: 0, inputs: inputs, rules: rules, random: &random)
        #expect(ahead == nil)
    }

    @Test func aCircleSideOffTheTargetsFacingAndAnAngleOverTheCapFail() throws {
        var random = ConditionRandom(seed: 4)
        var facing = Fixture.inputs(distance: 200)
        facing.targetYaw = 0
        facing.targetIsPlayer = true
        var loop = Loop()
        let issued3 = loop.advance(
            now: 0, inputs: facing, rules: Self.rules(circle: 1), random: &random
        )
        let started = try #require(Self.point(issued3))
        let angle = abs(atan2(started.y, started.x)) * 180 / .pi
        #expect(angle <= 42 * 0.75 + 0.01)
        #expect(loop.move?.alternate != nil)
        facing.targetYaw = .pi
        loop = Loop()
        let behind = loop.advance(
            now: 0, inputs: facing, rules: Self.rules(circle: 1), random: &random
        )
        #expect(behind == nil)
        var tight = Fixture.inputs(distance: 10)
        tight.actorRadius = 100
        loop = Loop()
        let capped = loop.advance(
            now: 0, inputs: tight, rules: Self.rules(circle: 1), random: &random
        )
        #expect(capped == nil)
    }

    @Test func aFallbackGoesOutWhileTheTargetFacesTheActorThenWaits() throws {
        var random = ConditionRandom(seed: 5)
        var inputs = Fixture.inputs(distance: 150)
        inputs.targetYaw = 0
        var loop = Loop()
        let rules = Self.rules(fallback: 1)
        let issued4 = loop.advance(
            now: 0, inputs: inputs, rules: rules, random: &random
        )
        let point = try #require(Self.point(issued4))
        #expect(abs(point.x - (Fixture.reach + 128)) < 0.01)
        let early = loop.advance(now: 0.3, inputs: inputs, rules: rules, random: &random)
        #expect(early == nil)
        let ended = loop.advance(
            now: 0.6, inputs: Fixture.inputs(distance: point.x), rules: rules, random: &random
        )
        #expect(ended == .hold)
        #expect(loop.holdsPosition(now: 1))
        #expect(!loop.holdsPosition(now: 2))
        inputs.targetYaw = .pi
        loop = Loop()
        let unseen = loop.advance(now: 0, inputs: inputs, rules: rules, random: &random)
        #expect(unseen == nil)
    }

    @Test func aFallbackIsCancelledWhenTheActorClosesInAndAMoveTimesOut() throws {
        var random = ConditionRandom(seed: 6)
        var loop = Loop()
        let rules = Self.rules(fallback: 1)
        let start = Fixture.inputs(distance: 150)
        let issued5 = loop.advance(
            now: 0, inputs: start, rules: rules, random: &random
        )
        _ = try #require(Self.point(issued5))
        let closer = loop.advance(
            now: 0.5, inputs: Fixture.inputs(distance: 100), rules: rules, random: &random
        )
        #expect(closer == .hold)
        #expect(loop.nextPass == 0.5 + 0.75)
        loop = Loop()
        let circle = Self.rules(circle: 1)
        let issued6 = loop.advance(
            now: 0, inputs: Fixture.inputs(distance: 200), rules: circle, random: &random
        )
        _ = try #require(Self.point(issued6))
        let stuck = loop.advance(
            now: Loop.timeoutSeconds, inputs: Fixture.inputs(distance: 200), rules: circle,
            random: &random
        )
        #expect(stuck == .hold)
    }

    /// A move no path reaches is refused, and a circle asks for its other side.
    @Test func aStyledFighterTriesItsMovesThroughTheMover() {
        let (runtime, world) = CombatLoopFixture.session()
        world.actors = [CombatActorObservation(
            key: CombatLoopFixture.opponent, feet: CombatLoopFixture.closeFeet,
            heading: -.pi / 2, name: "Opponent"
        )]
        var style = CombatStyleTuning.neutral
        style.offensiveMultiplier = 0
        style.circleMultiplier = 1
        world.styles[CombatLoopFixture.opponent] = style
        world.movementSucceeds = false
        CombatLoopFixture.engage(runtime, world)
        CombatLoopFixture.run(runtime, seconds: 10)
        let started = runtime.behaviors[CombatLoopFixture.opponent]?.closeMoveCount ?? 0
        #expect(started > 0)
        #expect(world.moveRequests.count > started)
    }

    @Test func theMachineWalksToItsMoveWhileSpacingAndHoldsWhenAnAttackStarts() {
        var settings = Fixture.neverCasting
        settings.attackChance = 0
        var close = CombatCloseRangeSettings()
        close.circleChance = 1
        close.fallbackChance = 0
        settings.closeRange = close
        var machine = Fixture.machine(settings: settings)
        let inputs = Fixture.inputs(distance: 100)
        Fixture.run(&machine, until: { $0.phase == .spacing }, inputs: inputs)
        let step = machine.step(seconds: Fixture.step, inputs: inputs)
        #expect(Self.point(step.command) != nil)
        #expect(step.pace == .walk)
        #expect(machine.closeMoveKind == "circle")
        #expect(machine.closeMoveCount == 1)
        let otherSide = machine.refuseCloseMove()
        #expect(otherSide != nil)
        let noSide = machine.refuseCloseMove()
        #expect(noSide == nil)

        var swings = settings
        swings.attackChance = 1
        machine = Fixture.machine(settings: swings)
        Fixture.run(&machine, until: { $0.phase == .spacing }, inputs: inputs)
        machine.closeMoves = Loop()
        let held = machine.leaveCloseMoves(machine.unchanged(), wasMoving: true)
        #expect(held.command == .hold)
    }
}
