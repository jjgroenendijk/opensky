// Satellite of M10AcceptanceTests (issue #166): the engine half of the M10 gate,
// with no fakes on the engine side at all.
//
// Split from the parent file because the two halves stand alone — the parent
// drives the sidebar panel through `FakeWorldProviders`, while everything here
// runs a real `WorldStateStore` wired to a real `GlobalStore` and a real
// `GameClock` exactly as `GameViewController` wires them, and a real
// `OpenSkySaveStore` writing to a temporary directory.
//
// This is where the gate's "identical state including journal-independent
// snapshot equality" is actually asserted. `WorldStateSnapshot.==` deliberately
// excludes the journal sequence, so a restored store compares equal to the store
// it was saved from even though the restore records nothing and advances no
// counter — the assertions below check both halves of that claim rather than
// only the equality.
//
// No game data: the plugin bytes every fixture parses are built in code.

import Foundation
@testable import opensky
import simd
import Testing

/// The clock the store's time-global redirect drives. A reference type because
/// `WorldStateStore.onTimeGlobalWrite` has to mutate it from a closure, exactly
/// as `GameViewController` mutates the renderer's clock.
private final class M10GameClockBox {
    var clock = GameClock()
}

/// A store, a plugin-default global index and a clock wired together the way
/// `GameViewController` wires them: every write goes through
/// `WorldStateStore.setGlobal(_:formID:defaults:)`, which redirects the five
/// clock-owned editor IDs into the clock and stores an override for everything
/// else.
@MainActor
private struct M10EngineSession {
    let world = WorldStateStore()
    let defaults: GlobalStore
    private let box = M10GameClockBox()

    init() throws {
        defaults = try GlobalFixture.store(M10EngineSession.globalRecords)
        let clockBox = box
        world.onTimeGlobalWrite = { timeGlobal, value in
            let previous = clockBox.clock.projectedValue(timeGlobal)
            clockBox.clock.setProjectedValue(value, for: timeGlobal)
            return previous
        }
    }

    var clock: GameClock {
        box.clock
    }

    /// One panel-level global write. Returns false when no loaded plugin
    /// defines the editor ID, which is the same answer the live bridge gives.
    @discardableResult
    func setGlobal(_ value: Float, editorID: String) -> Bool {
        guard let formID = defaults.formID(editorID: editorID) else { return false }
        return world.setGlobal(value, formID: formID, defaults: defaults)
    }

    /// Effective values for this instant, with the clock projecting the five
    /// time globals — the same call `GameViewController` makes.
    func resolution() -> GlobalResolution {
        world.globalResolution(defaults: defaults, clock: box.clock)
    }

    /// The vanilla time globals plus one ordinary short global to mutate. Every
    /// FormID and every value is invented.
    private static var globalRecords: Data {
        var records = Data()
        for (objectID, editorID, type, value) in [
            (UInt32(0x0800), "TimeScale", Global.ValueType.float, Float(20)),
            (0x0801, "GameHour", .float, 13),
            (0x0802, "GameDay", .short, 17),
            (0x0803, "GameMonth", .short, 8),
            (0x0804, "GameYear", .short, 201),
            (0x0805, "GameDaysPassed", .float, 0),
            (0x0806, "MyGold", .short, 100)
        ] {
            records += GlobalFixture.record(
                formID: objectID, editorID: editorID, type: type, value: value
            )
        }
        return records
    }
}

extension M10AcceptanceTests {
    // MARK: Step 7 — the five-step round trip on real engine objects

    /// The core proof of the gate, in the order the panel performs it: mutate a
    /// reference, mutate a global, scrub the clock, save, and load into a
    /// brand-new store and a brand-new clock. The restored session is in the
    /// identical end state, and the equality that proves it is journal
    /// independent.
    @Test @MainActor
    func theSessionRoundTripsThroughASaveSlotIntoAFreshInstance() throws {
        let session = try M10EngineSession()
        Self.mutateAReference(session.world)
        #expect(session.world.dirtyCount == 2)

        #expect(session.setGlobal(2500, editorID: "MyGold"))
        #expect(session.setGlobal(3600, editorID: GameClock.timescaleEditorID))
        #expect(session.world.overriddenGlobalCount == 2)

        // The clock scrub. `GameHour` is clock owned, so this moves the clock
        // and deliberately stores no third override.
        #expect(session.setGlobal(7.25, editorID: "GameHour"))
        #expect(session.clock.hourOfDay == 7.25)
        #expect(session.world.overriddenGlobalCount == 2)
        #expect(session.resolution().floatValue(editorID: "GameHour") == 7.25)

        let directory = try M10StateAcceptanceTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let saves = OpenSkySaveStore(directory: directory)
        try saves.save(
            snapshot: session.world.snapshot(),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            clock: session.clock,
            toSlot: Self.slot
        )
        let file = try saves.load(
            slot: Self.slot, verifyingAgainst: OpenSkySaveFixture.fingerprint
        )
        try Self.expectIdenticalRestoredSession(file, matching: session)
    }

    /// A clock scrub leaves no override behind but does leave a journal entry,
    /// which is what puts it in the panel's tail readout beside the reference
    /// and global writes. Both facts are asserted together because either one
    /// alone would look like a bug.
    @Test @MainActor
    func aClockScrubIsJournalledWithoutStoringAnOverride() throws {
        let session = try M10EngineSession()
        Self.mutateAReference(session.world)
        #expect(session.setGlobal(2500, editorID: "MyGold"))
        #expect(session.setGlobal(7.25, editorID: "GameHour"))

        // One shared counter across both rings, so ordering by sequence
        // reproduces the causal order the session performed the writes in.
        let componentSequences = session.world.journalEntries.map(\.sequence)
        let globalSequences = session.world.globalJournalEntries.map(\.sequence)
        #expect(componentSequences == [1, 2])
        #expect(globalSequences == [3, 4])
        #expect(session.world.nextJournalSequence == 5)

        let names = [
            GlobalFixture.key(0x0806): "MyGold",
            GlobalFixture.key(0x0801): "GameHour"
        ]
        let lines = session.world.globalJournalEntries.map {
            GameViewController.globalJournalLine($0, name: names[$0.key] ?? "?")
        }
        #expect(lines == ["3 set global MyGold = 2500", "4 set global GameHour = 7.25"])

        // The scrub stored nothing: only MyGold is overridden.
        #expect(session.world.sortedOverriddenGlobalKeys() == [GlobalFixture.key(0x0806)])
    }

    /// A pre-clock save carries no `CLOK` chunk. Loading one must restore the
    /// vanilla start rather than leave the previous session's date in place,
    /// which is the tolerance the additive chunk stream exists to provide.
    @Test @MainActor
    func aSaveWrittenWithoutAClockRestoresTheVanillaStart() throws {
        let session = try M10EngineSession()
        #expect(session.setGlobal(2500, editorID: "MyGold"))

        let directory = try M10StateAcceptanceTests.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let saves = OpenSkySaveStore(directory: directory)
        try saves.save(
            snapshot: session.world.snapshot(),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            toSlot: Self.slot
        )
        let file = try saves.load(slot: Self.slot)
        #expect(file.clock == nil)
        // The live bridge's fallback, asserted here so the behaviour is pinned
        // outside `GameViewController`, which a unit test cannot build.
        #expect((file.clock ?? GameClock()) == GameClock())
        #expect(file.snapshot.dirtyGlobalCount == 1)
    }

    // MARK: Shared engine state

    /// Slot every case here writes to. Named after the gate so a stray file is
    /// obviously a test artifact.
    static let slot = "m10-acceptance-engine"

    private static let disabledObjectID: UInt32 = 0x200
    private static let movedObjectID: UInt32 = 0x201
    private static let movedPosition = SIMD3<Float>(500, 600, 700)

    private static func referenceKey(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: objectID)
    }

    /// The two reference mutations the panel's Disable and Nudge buttons make,
    /// applied through the same `WorldStateStore.set` the live bridge calls.
    @MainActor
    private static func mutateAReference(_ store: WorldStateStore) {
        let cell = CellSceneLocation.exterior(CellCoordinate(x: 6, y: -2))
        #expect(store.set(
            ReferenceEnableState.disabled,
            for: referenceKey(disabledObjectID),
            in: cell
        ))
        #expect(store.set(
            ReferenceTransformOverride(position: movedPosition),
            for: referenceKey(movedObjectID),
            in: cell
        ))
    }

    /// Everything the gate means by "identical state": a fresh store restored
    /// from the file compares equal to the saved one, the clock came back to the
    /// same instant, every global resolves to the same value, and the restore
    /// itself recorded nothing.
    @MainActor
    private static func expectIdenticalRestoredSession(
        _ file: OpenSkySaveFile, matching session: M10EngineSession
    ) throws {
        let fresh = WorldStateStore()
        fresh.restore(from: file.snapshot)
        let restoredClock = try #require(file.clock)

        // Journal independence, both halves. The two snapshots carry different
        // sequence numbers — five writes against none — and still compare
        // equal, because `==` is entries, globals and the allocator position
        // only.
        #expect(session.world.snapshot().sequence == 6)
        #expect(fresh.snapshot().sequence == 1)
        #expect(fresh.snapshot() == session.world.snapshot())
        #expect(fresh.journalEntries.isEmpty)
        #expect(fresh.globalJournalEntries.isEmpty)

        #expect(fresh.dirtyCount == 2)
        #expect(fresh.overriddenGlobalCount == 2)
        #expect(
            fresh.component(ReferenceEnableState.self, for: referenceKey(disabledObjectID))
                == .disabled
        )
        let transform = try #require(
            fresh.component(ReferenceTransformOverride.self, for: referenceKey(movedObjectID))
        )
        #expect(transform.position == movedPosition)

        #expect(restoredClock == session.clock)
        #expect(restoredClock.hourOfDay == 7.25)
        let restored = fresh.globalResolution(defaults: session.defaults, clock: restoredClock)
        #expect(restored.floatValue(editorID: "MyGold") == 2500)
        #expect(restored.floatValue(editorID: GameClock.timescaleEditorID) == 3600)
        #expect(restored.floatValue(editorID: "GameHour") == 7.25)
        // What the panel's clock readout would show for the restored session.
        let sample = RuntimeStateClockSnapshot(
            clock: restoredClock, timescale: 3600, isPaused: false
        )
        #expect(sample.timeText == "07:15")
        // Only the hour was scrubbed, so the date is still the vanilla start.
        #expect(sample.dateText == "17 Last Seed, 4E 201")
    }
}
