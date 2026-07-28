// The clock-reading condition functions and the seeded random source.
//
// Everything here is deterministic: game time comes from a `GameClock` the test
// builds, and `GetRandomPercent` draws from a seeded `ConditionRandom`.

import Foundation
@testable import opensky
import Testing

struct ConditionTimeFunctionTests {
    private static let getCurrentTime: UInt16 = 18
    private static let getRandomPercent: UInt16 = 77
    private static let getDayOfWeek: UInt16 = 170

    // MARK: - GetCurrentTime

    @Test func getCurrentTimeReadsTheClockAsADecimalHour() throws {
        // 4:30am is 4.5, not 4.30.
        var evaluator = try ConditionEvaluatorFixture.evaluator(clock: GameClock(hour: 4.5))
        let exact = try ConditionEvaluatorFixture.comparing(
            functionIndex: Self.getCurrentTime, 0, 4.5
        )
        let before = try ConditionEvaluatorFixture.comparing(
            functionIndex: Self.getCurrentTime, 4, 5
        )
        #expect(evaluator.evaluate(exact).isTrue)
        #expect(evaluator.evaluate(before).isTrue)
        #expect(evaluator.tally.isClean)
    }

    @Test func timeFunctionAnswersUnderAnUnresolvableRunOn() throws {
        // Only functions that need a reference care about the run-on, so a
        // clock read still answers with no subject bound.
        var evaluator = ConditionEvaluator(context: ConditionContext(clock: GameClock(hour: 9)))
        let condition = try ConditionEvaluatorFixture.comparing(
            functionIndex: Self.getCurrentTime, 3, 6, runOn: 0
        )
        #expect(evaluator.evaluate(condition).isTrue)
        #expect(evaluator.tally.isClean)
    }

    @Test func getCurrentTimeFallsBackToTheGameHourGlobal() throws {
        let globals = try ConditionEvaluatorFixture.globals([
            ConditionEvaluatorFixture.GlobalSpec(
                formID: 0x0000_0200, editorID: "GameHour", value: 21
            )
        ])
        var evaluator = ConditionEvaluator(context: ConditionContext(globals: globals))
        let condition = try ConditionEvaluatorFixture.comparing(
            functionIndex: Self.getCurrentTime, 0, 21
        )
        #expect(evaluator.evaluate(condition).isTrue)
        #expect(evaluator.tally.isClean)
    }

    @Test func getCurrentTimeWithoutAClockOrGlobalIsTagged() throws {
        var evaluator = ConditionEvaluator(context: ConditionContext())
        let condition = try ConditionEvaluatorFixture.comparing(
            functionIndex: Self.getCurrentTime, 0, 12
        )
        let outcome = evaluator.evaluate(condition)
        #expect(!outcome.isTrue)
        #expect(outcome.failures == [.unavailableClock])
        #expect(evaluator.tally.unavailableClock == 1)
    }

    // MARK: - GetDayOfWeek

    @Test func getDayOfWeekAdvancesOncePerDayAndWraps() {
        var clock = GameClock(year: 201, month: 8, day: 17, hour: 0)
        let start = ConditionFunctions.dayOfWeek(of: clock)
        #expect((0 ... 6).contains(start))
        for step in 1 ... 8 {
            // One game day at timescale 1 is 86400 wall seconds, fed in whole
            // hours so the arithmetic stays exact.
            for _ in 0 ..< 24 {
                clock.advance(wallDelta: 3600, timescale: 1)
            }
            #expect(ConditionFunctions.dayOfWeek(of: clock) == (start + step) % 7)
        }
        #expect(ConditionFunctions.weekdayNames.count == 7)
        #expect(ConditionFunctions.weekdayNames.first == "Sundas")
        #expect(ConditionFunctions.weekdayNames.last == "Loredas")
    }

    @Test func getDayOfWeekIsReadableAsACondition() throws {
        let clock = GameClock(year: 201, month: 8, day: 17, hour: 12)
        var evaluator = try ConditionEvaluatorFixture.evaluator(clock: clock)
        let expected = Float(ConditionFunctions.dayOfWeek(of: clock))
        let condition = try ConditionEvaluatorFixture.comparing(
            functionIndex: Self.getDayOfWeek, 0, expected
        )
        #expect(evaluator.evaluate(condition).isTrue)
        #expect(evaluator.tally.isClean)
    }

    @Test func getDayOfWeekWithoutAClockIsTagged() throws {
        var evaluator = ConditionEvaluator(context: ConditionContext())
        let condition = try ConditionEvaluatorFixture.comparing(
            functionIndex: Self.getDayOfWeek, 0, 0
        )
        #expect(evaluator.evaluate(condition).failures == [.unavailableClock])
    }

    // MARK: - GetRandomPercent

    @Test func randomSourceIsSeedDeterministicAndCoversZeroTo99() {
        var first = ConditionRandom(seed: 42)
        var second = ConditionRandom(seed: 42)
        var other = ConditionRandom(seed: 43)
        let firstDraws = (0 ..< 32).map { _ in first.percent() }
        let secondDraws = (0 ..< 32).map { _ in second.percent() }
        let otherDraws = (0 ..< 32).map { _ in other.percent() }
        #expect(firstDraws == secondDraws)
        #expect(firstDraws != otherDraws)

        var stream = ConditionRandom(seed: 7)
        var seen = Set<Int>()
        for _ in 0 ..< 20000 {
            let draw = stream.percent()
            #expect((0 ... 99).contains(draw))
            seen.insert(draw)
        }
        // 0...99 inclusive, and never 100.
        #expect(seen.count == 100)
        #expect(seen.contains(0))
        #expect(seen.contains(99))
        #expect(!seen.contains(100))
    }

    @Test func getRandomPercentDrawsFromTheInjectedStream() throws {
        var expected = ConditionRandom(seed: 1234)
        let draws = (0 ..< 4).map { _ in Float(expected.percent()) }

        var evaluator = try ConditionEvaluator(context: ConditionContext(
            globals: ConditionEvaluatorFixture.standardGlobals(),
            random: ConditionRandom(seed: 1234)
        ))
        for draw in draws {
            let condition = try ConditionEvaluatorFixture.comparing(
                functionIndex: Self.getRandomPercent, 0, draw
            )
            #expect(evaluator.evaluate(condition).isTrue, "expected draw \(draw)")
        }
        #expect(evaluator.tally.isClean)
        // The evaluator advanced the caller's stream rather than copying it.
        #expect(evaluator.context.random == expected)
    }
}
