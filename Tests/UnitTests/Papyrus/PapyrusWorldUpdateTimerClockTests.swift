// Update-timer clock policy (issue #277): family-scoped unregistration,
// paused frames holding both families, and the game-time sampling rules —
// backward scrubs contribute nothing and re-anchor, one step's forward
// contribution caps at 24 game hours, and a capped scrub fires each due
// timer at most once.

@testable import opensky
import Testing

@MainActor
struct PapyrusWorldUpdateTimerClockTests {
    @Test func unregisterForUpdateClearsOnlyTheRealTimeFamily() throws {
        let session = try PapyrusUpdateTimerFixture.session()
        let clock = GameClock(hour: 12)
        _ = session.world.stepFixed(gameClock: clock)
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForSingleUpdate", interval: 0
        )
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForUpdate", interval: 0
        )
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForSingleUpdateGameTime", interval: 0
        )
        #expect(session.world.updateTimers.pendingCount == 3)
        PapyrusUpdateTimerFixture.invoke(session, "UnregisterForUpdate")
        #expect(session.world.updateTimers.pendingCount == 1)
        _ = session.world.stepFixed(gameClock: clock)
        #expect(PapyrusUpdateTimerFixture.updateNotes(session).isEmpty)
        #expect(PapyrusUpdateTimerFixture.gameTimeNotes(session).count == 1)
    }

    @Test func unregisterForUpdateGameTimeClearsOnlyTheGameTimeFamily() throws {
        let session = try PapyrusUpdateTimerFixture.session()
        let clock = GameClock(hour: 12)
        _ = session.world.stepFixed(gameClock: clock)
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForSingleUpdateGameTime", interval: 0
        )
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForUpdateGameTime", interval: 0
        )
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForSingleUpdate", interval: 0
        )
        #expect(session.world.updateTimers.pendingCount == 3)
        PapyrusUpdateTimerFixture.invoke(session, "UnregisterForUpdateGameTime")
        #expect(session.world.updateTimers.pendingCount == 1)
        _ = session.world.stepFixed(gameClock: clock)
        #expect(PapyrusUpdateTimerFixture.updateNotes(session).count == 1)
        #expect(PapyrusUpdateTimerFixture.gameTimeNotes(session).isEmpty)
    }

    @Test func pausedFramesAdvanceNeitherFamily() throws {
        let session = try PapyrusUpdateTimerFixture.session()
        let clock = GameClock(hour: 12)
        _ = session.world.stepFixed(gameClock: clock)
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForSingleUpdate", interval: 0
        )
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForSingleUpdateGameTime", interval: 1
        )
        // Paused frames arrive as delta 0: zero fixed steps, so neither
        // family advances and the jumped clock is never even sampled.
        let jumped = PapyrusUpdateTimerFixture.advanced(clock, hours: 10)
        for _ in 0 ..< 5 {
            let report = session.world.advance(delta: 0, gameClock: jumped)
            #expect(report.steps == 0)
        }
        #expect(PapyrusUpdateTimerFixture.updateNotes(session).isEmpty)
        #expect(PapyrusUpdateTimerFixture.gameTimeNotes(session).isEmpty)
        // One real step with the clock back at its pre-pause value: the real
        // timer fires, and the game-time timer does not — which is only
        // possible if the paused frames never sampled the jumped clock.
        _ = session.world.stepFixed(gameClock: clock)
        #expect(PapyrusUpdateTimerFixture.updateNotes(session).count == 1)
        #expect(PapyrusUpdateTimerFixture.gameTimeNotes(session).isEmpty)
        _ = session.world.stepFixed(
            gameClock: PapyrusUpdateTimerFixture.advanced(clock, hours: 2)
        )
        #expect(PapyrusUpdateTimerFixture.gameTimeNotes(session).count == 1)
    }

    @Test func backwardClockScrubFiresNothingAndReAnchors() throws {
        let session = try PapyrusUpdateTimerFixture.session()
        var clock = GameClock(hour: 12)
        _ = session.world.stepFixed(gameClock: clock)
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForSingleUpdateGameTime", interval: 1
        )
        clock.setHour(6)
        _ = session.world.stepFixed(gameClock: clock)
        #expect(PapyrusUpdateTimerFixture.gameTimeNotes(session).isEmpty)
        #expect(session.world.updateTimers.elapsedGameHours == 0)
        // One game hour forward from the re-anchored (earlier) clock is a
        // full hour of contribution, so the timer fires.
        _ = session.world.stepFixed(
            gameClock: PapyrusUpdateTimerFixture.advanced(clock, hours: 1)
        )
        #expect(PapyrusUpdateTimerFixture.gameTimeNotes(session).count == 1)
    }

    @Test func aCappedForwardScrubFiresEachDueTimerExactlyOnce() throws {
        let session = try PapyrusUpdateTimerFixture.session()
        let clock = GameClock(hour: 12)
        _ = session.world.stepFixed(gameClock: clock)
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForUpdateGameTime", interval: 1
        )
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForSingleUpdateGameTime", interval: 2
        )
        // A thirty-day scrub contributes one capped day, which is past both
        // deadlines many times over — yet each slot fires exactly once: the
        // repeating timer re-anchors instead of queueing catch-ups.
        let scrubbed = PapyrusUpdateTimerFixture.advanced(clock, hours: 720)
        _ = session.world.stepFixed(gameClock: scrubbed)
        #expect(PapyrusUpdateTimerFixture.gameTimeNotes(session).count == 2)
        #expect(session.world.updateTimers.elapsedGameHours == 24)
        // No game time passes: the re-anchored repeating timer holds.
        _ = session.world.stepFixed(gameClock: scrubbed)
        #expect(PapyrusUpdateTimerFixture.gameTimeNotes(session).count == 2)
        // One more game hour reaches the re-anchored deadline once.
        _ = session.world.stepFixed(
            gameClock: PapyrusUpdateTimerFixture.advanced(scrubbed, hours: 1)
        )
        #expect(PapyrusUpdateTimerFixture.gameTimeNotes(session).count == 3)
    }
}
