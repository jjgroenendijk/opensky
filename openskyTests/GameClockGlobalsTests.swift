// One source of truth between the game clock and the vanilla time globals
// (issue #164): reads through `GlobalResolution` project from the clock, and a
// `setGlobal` on a clock-owned editor ID moves the clock instead of storing an
// override. See docs/engine/game-clock.md.

import Foundation
@testable import opensky
import Testing

@MainActor
struct GameClockGlobalsTests {
    private static func store() throws -> GlobalStore {
        try GlobalFixture.store(
            GlobalFixture.record(formID: 0x0800, editorID: "TimeScale", type: .float, value: 20)
                + GlobalFixture.record(
                    formID: 0x0801, editorID: "GameHour", type: .float, value: 12
                )
                + GlobalFixture.record(formID: 0x0802, editorID: "GameDay", type: .short, value: 17)
                + GlobalFixture.record(
                    formID: 0x0803, editorID: "GameMonth", type: .short, value: 8
                )
                + GlobalFixture.record(
                    formID: 0x0804, editorID: "GameYear", type: .short, value: 201
                )
                + GlobalFixture.record(
                    formID: 0x0805, editorID: "GameDaysPassed", type: .float, value: 0
                )
        )
    }

    /// A store whose time-global writes drive `clock`, wired the same way
    /// `GameViewController.wireStreaming` wires the renderer's clock.
    private func makeStoreAndClock() throws -> (WorldStateStore, () -> GameClock) {
        let world = WorldStateStore()
        let box = ClockBox()
        world.onTimeGlobalWrite = { timeGlobal, value in
            let previous = box.clock.projectedValue(timeGlobal)
            box.clock.setProjectedValue(value, for: timeGlobal)
            return previous
        }
        return (world, { box.clock })
    }

    @Test func resolutionProjectsTimeGlobalsFromTheClock() throws {
        let defaults = try Self.store()
        let clock = GameClock(year: 203, month: 10, day: 5, hour: 18.5)
        let resolution = GlobalResolution(defaults: defaults, clock: clock)
        #expect(resolution.floatValue(editorID: "GameHour") == clock.hourOfDay)
        #expect(resolution.floatValue(editorID: "GameDay") == 5)
        #expect(resolution.floatValue(editorID: "GameMonth") == 10)
        #expect(resolution.floatValue(editorID: "GameYear") == 203)
        #expect(resolution.floatValue(editorID: "GameDaysPassed") == clock.daysPassed)
        // Declared types survive projection: a short global stays a short.
        #expect(resolution.value(editorID: "GameDay")?.type == .short)
        // TimeScale is not clock-owned and still reads its plugin default.
        #expect(resolution.floatValue(editorID: "TimeScale") == 20)
    }

    @Test func projectionOutranksAStaleOverride() throws {
        let defaults = try Self.store()
        let clock = GameClock(year: 201, month: 8, day: 17, hour: 6)
        let resolution = GlobalResolution(
            defaults: defaults,
            overrides: [GlobalFixture.key(0x0801): GlobalValue(type: .float, rawValue: 23)],
            clock: clock
        )
        #expect(
            resolution.floatValue(editorID: "GameHour") == 6,
            "the clock answers even when an override was stored"
        )
    }

    @Test func settingATimeGlobalMovesTheClockAndStoresNoOverride() throws {
        let defaults = try Self.store()
        let (world, clock) = try makeStoreAndClock()

        let gameHour = try #require(defaults.formID(editorID: "GameHour"))
        #expect(world.setGlobal(6, formID: gameHour, defaults: defaults))
        #expect(clock().hourOfDay == 6)
        #expect(world.overriddenGlobalCount == 0, "clock writes never store an override")

        // Round trip: the mutated clock projects back through a fresh
        // resolution built the way every consumer builds one.
        let resolution = world.globalResolution(defaults: defaults, clock: clock())
        #expect(resolution.floatValue(editorID: "GameHour") == 6)
        #expect(resolution.floatValue(editorID: "GameDay") == 17)

        let gameYear = try #require(defaults.formID(editorID: "GameYear"))
        #expect(world.setGlobal(205, formID: gameYear, defaults: defaults))
        #expect(clock().year == 205)
    }

    @Test func timeGlobalWritesJournalWithoutFiringGlobalMutation() throws {
        let defaults = try Self.store()
        let (world, _) = try makeStoreAndClock()
        var mutationFired = false
        world.onGlobalMutation = { _ in mutationFired = true }

        let gameHour = try #require(defaults.formID(editorID: "GameHour"))
        #expect(world.setGlobal(6, formID: gameHour, defaults: defaults))
        let entry = try #require(world.globalJournalEntries.last)
        #expect(entry.key == GlobalFixture.key(0x0801))
        #expect(entry.oldValue == GlobalValue(type: .float, rawValue: 13))
        #expect(entry.newValue == GlobalValue(type: .float, rawValue: 6))
        #expect(!mutationFired, "a scrub must not reroll the weather")

        // Writing the projected value again is a no-op and journals nothing.
        let count = world.globalJournalEntries.count
        #expect(!world.setGlobal(6, formID: gameHour, defaults: defaults))
        #expect(world.globalJournalEntries.count == count)

        // A non-time global still takes the ordinary override path.
        let timeScale = try #require(defaults.formID(editorID: "TimeScale"))
        #expect(world.setGlobal(40, formID: timeScale, defaults: defaults))
        #expect(mutationFired)
        #expect(world.overriddenGlobalCount == 1)
    }

    @Test func withoutAClockHandlerTimeGlobalsFallBackToOverrides() throws {
        let defaults = try Self.store()
        let world = WorldStateStore()
        let gameHour = try #require(defaults.formID(editorID: "GameHour"))
        #expect(world.setGlobal(6, formID: gameHour, defaults: defaults))
        #expect(world.overriddenGlobalCount == 1)
        #expect(world.globalResolution(defaults: defaults)
            .floatValue(editorID: "GameHour") == 6)
    }
}

/// Reference box so the test's redirect closure can mutate a clock the
/// assertions read back, mirroring how the renderer owns the real one.
@MainActor
private final class ClockBox {
    var clock = GameClock()
}
