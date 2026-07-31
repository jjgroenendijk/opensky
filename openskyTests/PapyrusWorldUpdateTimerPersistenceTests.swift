// Update-timer save seam and lifecycle containment (issue #277):
// `timerStates()` / `restore(timerStates:)` round trip at the runtime level,
// persistent-only snapshot membership, the unknown-target skip tally, restore
// re-anchoring against the current clock, and cell detach purging a
// non-persistent instance's timers. Stage B serializes these states into the
// save chunk; nothing here touches bytes.

@testable import opensky
import Testing

@MainActor
struct PapyrusWorldUpdateTimerPersistenceTests {
    static let transientScript = "OtherScript"
    static let transientID: UInt32 = 0x602

    static var transientKey: PapyrusInstanceKey {
        PapyrusWorldFixture.key(objectID: transientID, script: transientScript)
    }

    /// One persistent scripted reference and one non-persistent one, so the
    /// snapshot has something it must include and something it must not.
    private func twoReferenceSession() throws -> PapyrusWorldFixture.Session {
        let persistent = try PapyrusWorldFixture.referenceEntry(
            objectID: PapyrusUpdateTimerFixture.refID,
            scripts: [
                VMADFixture.Script(
                    PapyrusUpdateTimerFixture.scriptName, properties: []
                )
            ],
            isPersistent: true
        )
        let transient = try PapyrusWorldFixture.referenceEntry(
            objectID: Self.transientID,
            scripts: [VMADFixture.Script(Self.transientScript, properties: [])],
            isPersistent: false
        )
        let session = PapyrusWorldFixture.session(
            objects: [
                PapyrusUpdateTimerFixture.timerScript(),
                PapyrusUpdateTimerFixture.timerScript(Self.transientScript)
            ],
            entries: [persistent, transient]
        )
        PapyrusWorldFixture.drain(session.world)
        return session
    }

    /// Builds the source session, arms a real and a game-time single-shot on
    /// the persistent instance plus a real one on the transient instance,
    /// then runs ten steps so the real slot has a partial delay left.
    private func snapshotStates(
        clock: GameClock
    ) throws -> [PapyrusTimerState] {
        let source = try twoReferenceSession()
        _ = source.world.stepFixed(gameClock: clock)
        guard
            let persistentHandle = source.world
                .instancesByKey[PapyrusUpdateTimerFixture.instanceKey],
            let transientHandle = source.world.instancesByKey[Self.transientKey]
        else {
            Issue.record("Fixture instances missing")
            return []
        }
        source.world.registerUpdateTimer(
            handle: persistentHandle, slot: .realSingleShot, interval: 1
        )
        source.world.registerUpdateTimer(
            handle: persistentHandle, slot: .gameTimeSingleShot, interval: 3
        )
        source.world.registerUpdateTimer(
            handle: transientHandle, slot: .realSingleShot, interval: 1
        )
        for _ in 0 ..< 10 {
            _ = source.world.stepFixed(gameClock: clock)
        }
        return source.world.timerStates()
    }

    @Test func timerStatesRoundTripIntoAFreshRuntime() throws {
        let clock = GameClock(hour: 12)
        let states = try snapshotStates(clock: clock)
        // Persistent instance only, in stable slot order, with the delay
        // stored as time remaining rather than an absolute deadline.
        #expect(states.map(\.slot) == [.realSingleShot, .gameTimeSingleShot])
        #expect(states.allSatisfy {
            $0.key == PapyrusUpdateTimerFixture.instanceKey
        })
        let expectedRemaining = max(0, 1.0 - Double(10) * (1.0 / 30.0))
        #expect(states.first?.remaining == expectedRemaining)
        #expect(states.first?.interval == 1.0)
        #expect(states.last?.remaining == 3.0)

        let target = try twoReferenceSession()
        let unknown = PapyrusTimerState(
            key: PapyrusWorldFixture.key(objectID: 0x999, script: "GhostScript"),
            slot: .realSingleShot,
            interval: 1,
            remaining: 0
        )
        target.world.restore(timerStates: states + [unknown])
        #expect(target.world.skips.counts[.unknownSaveTimerTarget] == 1)
        #expect(target.world.updateTimers.pendingCount == 2)

        // The game time that passed between save and load must not count:
        // the first sample of a far-future clock only anchors.
        let loadClock = PapyrusUpdateTimerFixture.advanced(clock, hours: 100)
        _ = target.world.stepFixed(gameClock: loadClock)
        #expect(PapyrusUpdateTimerFixture.gameTimeNotes(target).isEmpty)

        // The real slot fires after exactly its remaining delay, counted
        // from the restore.
        var stepsSinceRestore = 1
        while
            PapyrusUpdateTimerFixture.updateNotes(target).isEmpty,
            stepsSinceRestore < 64
        {
            stepsSinceRestore += 1
            _ = target.world.stepFixed(gameClock: loadClock)
        }
        #expect(stepsSinceRestore == PapyrusUpdateTimerFixture.dueStep(
            interval: expectedRemaining, stepSeconds: 1.0 / 30.0
        ))
        #expect(PapyrusUpdateTimerFixture.updateNotes(target).count == 1)

        // Three game hours past the load anchor fires the restored
        // game-time slot.
        _ = target.world.stepFixed(
            gameClock: PapyrusUpdateTimerFixture.advanced(loadClock, hours: 3)
        )
        #expect(PapyrusUpdateTimerFixture.gameTimeNotes(target).count == 1)
    }

    @Test func detachPurgesANonPersistentInstancesTimers() throws {
        let session = try PapyrusUpdateTimerFixture.session(isPersistent: false)
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForSingleUpdate", interval: 0
        )
        PapyrusUpdateTimerFixture.invoke(
            session, "RegisterForUpdateGameTime", interval: 0
        )
        #expect(session.world.updateTimers.pendingCount == 2)
        session.world.detach(cell: PapyrusWorldFixture.cell)
        #expect(session.world.updateTimers.pendingCount == 0)
        #expect(session.world.timerStates().isEmpty)
        _ = session.world.stepFixed()
        #expect(PapyrusUpdateTimerFixture.updateNotes(session).isEmpty)
        #expect(PapyrusUpdateTimerFixture.gameTimeNotes(session).isEmpty)
    }
}
