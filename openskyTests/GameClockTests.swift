// GameClock advancement, calendar derivation and scrubbing (issue #164).
// Calendar facts asserted here follow UESP Lore:Calendar and Skyrim:Time as
// cited in opensky/World/GameClock.swift. See docs/engine/game-clock.md.

import Foundation
@testable import opensky
import Testing

struct GameClockTests {
    // MARK: - Vanilla start

    @Test func vanillaStartIsSeventeenthOfLastSeed4E201() {
        let clock = GameClock()
        #expect(clock.year == 201)
        #expect(clock.month == 8)
        #expect(clock.monthName == "Last Seed")
        #expect(clock.day == 17)
        #expect(clock.hourOfDay == GameClock.defaultStartHour)
    }

    @Test func calendarTablesMatchUESP() {
        #expect(GameClock.monthNames.count == 12)
        #expect(GameClock.monthNames.first == "Morning Star")
        #expect(GameClock.monthNames.last == "Evening Star")
        #expect(GameClock.monthLengths == [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])
        #expect(GameClock.daysPerYear == 365)
    }

    // MARK: - Advancement

    @Test func advancementIsDeterministicAcrossDeltaSequences() {
        let deltas: [Float] = [0.016, 0.033, 0.1, 0, 0.008, 2.5, 0.016]
        var first = GameClock()
        var second = GameClock()
        for delta in deltas {
            first.advance(wallDelta: delta, timescale: 20)
        }
        for delta in deltas {
            second.advance(wallDelta: delta, timescale: 20)
        }
        #expect(first == second)
    }

    @Test func advanceScalesWallDeltaByTimescale() {
        var clock = GameClock(year: 201, month: 8, day: 17, hour: 12)
        clock.advance(wallDelta: 90, timescale: 20)
        // 90 real seconds at timescale 20 = 1800 game seconds = half an hour.
        #expect(abs(clock.hourOfDay - 12.5) < 1e-5)
        #expect(clock.day == 17)
    }

    @Test func timescaleChangesMidFlight() {
        var clock = GameClock(year: 201, month: 8, day: 17, hour: 0)
        clock.advance(wallDelta: 10, timescale: 20) // 200 game seconds
        clock.advance(wallDelta: 10, timescale: 40) // 400 game seconds
        let start = GameClock(year: 201, month: 8, day: 17, hour: 0)
        #expect(clock.totalGameSeconds - start.totalGameSeconds == 600)
    }

    @Test func pausedDeltasFreezeGameTimeWithNoJump() {
        // Pause is a zero wall delta, exactly what FrameSimClock emits while
        // paused; resuming yields one ordinary frame delta, never the gap.
        var frameClock = FrameSimClock()
        var clock = GameClock()
        let before = clock
        _ = frameClock.advance(to: 0, paused: false) // first tick -> 0
        clock.advance(wallDelta: frameClock.advance(to: 10, paused: true), timescale: 20)
        clock.advance(wallDelta: frameClock.advance(to: 60, paused: true), timescale: 20)
        #expect(clock == before, "paused ticks advance nothing")
        let resumed = frameClock.advance(to: 60.016, paused: false)
        clock.advance(wallDelta: resumed, timescale: 20)
        let elapsed = clock.totalGameSeconds - before.totalGameSeconds
        #expect(abs(elapsed - Double(resumed) * 20) < 1e-6, "resume carries one frame only")
    }

    @Test func timescaleAndDeltaAreClampedDefensively() {
        var clock = GameClock()
        let before = clock
        clock.advance(wallDelta: -5, timescale: 20)
        clock.advance(wallDelta: Float.nan, timescale: 20)
        clock.advance(wallDelta: 1, timescale: -100)
        #expect(clock == before, "negative time never runs, backwards or forwards")
        clock.advance(wallDelta: 1, timescale: Float.greatestFiniteMagnitude)
        let elapsed = clock.totalGameSeconds - before.totalGameSeconds
        #expect(elapsed == Double(GameClock.timescaleRange.upperBound))
    }

    // MARK: - Calendar rollover

    @Test func dayRollsOverAtMidnight() {
        var clock = GameClock(year: 201, month: 8, day: 17, hour: 23)
        clock.advance(wallDelta: 2 * 3600, timescale: 1) // two game hours
        #expect(clock.day == 18)
        #expect(clock.month == 8)
        #expect(abs(clock.hourOfDay - 1) < 1e-5)
    }

    @Test func monthRollsOverAfterItsLastDay() {
        var clock = GameClock(year: 201, month: 8, day: 31, hour: 23)
        clock.advance(wallDelta: 2 * 3600, timescale: 1)
        #expect(clock.month == 9)
        #expect(clock.monthName == "Hearthfire")
        #expect(clock.day == 1)
        #expect(clock.year == 201)
    }

    @Test func yearRollsOverAfterEveningStar() {
        var clock = GameClock(year: 201, month: 12, day: 31, hour: 23)
        clock.advance(wallDelta: 2 * 3600, timescale: 1)
        #expect(clock.year == 202)
        #expect(clock.month == 1)
        #expect(clock.monthName == "Morning Star")
        #expect(clock.day == 1)
    }

    // MARK: - Scrubbing

    @Test func scrubThenAdvanceContinuesFromTheScrubbedHour() {
        var clock = GameClock()
        clock.setHour(6)
        #expect(clock.hourOfDay == 6)
        #expect(clock.day == 17, "scrubbing the hour keeps the date")
        clock.advance(wallDelta: 3600, timescale: 1)
        #expect(abs(clock.hourOfDay - 7) < 1e-5)
        #expect(clock.day == 17)
    }

    @Test func hourTwentyFourWrapsToMidnightOfTheSameDay() {
        var clock = GameClock()
        clock.setHour(24)
        #expect(clock.hourOfDay == 0)
        #expect(clock.day == 17)
    }

    @Test func dateScrubsClampIntoTheCalendar() {
        var clock = GameClock()
        clock.setMonth(2) // Sun's Dawn has 28 days; day 17 fits
        #expect(clock.month == 2)
        #expect(clock.day == 17)
        clock.setDay(31)
        #expect(clock.day == 28, "day clamps into Sun's Dawn")
        clock.setDay(1)
        clock.setMonth(99)
        #expect(clock.month == 12)
        clock.setYear(-4)
        #expect(clock.year == 0)
    }

    @Test func daysPassedRoundTripsAndKeepsWholeDayHours() {
        var clock = GameClock(year: 201, month: 8, day: 17, hour: 9)
        let before = clock.daysPassed
        clock.setDaysPassed(before + 7)
        #expect(abs(clock.hourOfDay - 9) < 1e-4, "adding whole days keeps the hour")
        #expect(clock.day == 24)
        #expect(abs(clock.daysPassed - (before + 7)) < 1e-4)
    }

    // MARK: - Time-global projection

    @Test func timeGlobalsClassifyCaseInsensitively() {
        #expect(GameClock.TimeGlobal(editorID: "gamehour") == .gameHour)
        #expect(GameClock.TimeGlobal(editorID: "GAMEDAYSPASSED") == .gameDaysPassed)
        #expect(GameClock.TimeGlobal(editorID: "GameDay") == .gameDay)
        #expect(GameClock.TimeGlobal(editorID: "GameMonth") == .gameMonth)
        #expect(GameClock.TimeGlobal(editorID: "GameYear") == .gameYear)
        #expect(
            GameClock.TimeGlobal(editorID: "TimeScale") == nil,
            "TimeScale stays a real global"
        )
        #expect(GameClock.TimeGlobal(editorID: "WeatherChanceRain") == nil)
    }

    @Test func projectedValuesMirrorTheCalendar() {
        let clock = GameClock(year: 203, month: 10, day: 5, hour: 18.5)
        #expect(abs(clock.projectedValue(.gameHour) - 18.5) < 1e-5)
        #expect(clock.projectedValue(.gameDay) == 5)
        #expect(clock.projectedValue(.gameMonth) == 10)
        #expect(clock.projectedValue(.gameYear) == 203)
    }

    @Test func settingProjectedValuesMovesTheClock() {
        var clock = GameClock()
        clock.setProjectedValue(4.25, for: .gameHour)
        #expect(abs(clock.hourOfDay - 4.25) < 1e-5)
        clock.setProjectedValue(3, for: .gameDay)
        #expect(clock.day == 3)
        clock.setProjectedValue(10, for: .gameMonth)
        #expect(clock.monthName == "Frostfall")
        clock.setProjectedValue(203, for: .gameYear)
        #expect(clock.year == 203)
        clock.setProjectedValue(Float.nan, for: .gameHour)
        #expect(abs(clock.hourOfDay - 4.25) < 1e-5, "non-finite writes are ignored")
    }
}
