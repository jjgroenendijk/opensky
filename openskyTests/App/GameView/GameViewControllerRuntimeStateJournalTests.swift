// Live-bridge coverage for the journal tail the World > Runtime State Inspect
// section shows (issue #166, roadmap item 10.2).
//
// The claim under test is the one the milestone gate rests on: reference
// mutations and global mutations are recorded on two separate rings that share
// one monotonic sequence counter, so ordering the merged lines by `sequence`
// reproduces the exact order the session performed them in. A tail built from
// the component ring alone — which is what M10.1 shipped — would show none of
// the M10.2 mutations at all.
//
// Everything here is synthetic: GLOB records built in code by `GlobalFixture`,
// no renderer, no game data.

import AppKit
@testable import opensky
import Testing

struct GameViewControllerRuntimeStateJournalTests {
    @Test @MainActor
    func journalTailInterleavesReferenceAndGlobalWritesBySequence() throws {
        let controller = GameViewController()
        controller.globalStore = try Self.store()

        controller.worldState.set(ReferenceEnableState(isEnabled: false), for: Self.referenceKey)
        controller.setGlobalValue(120, editorID: "TimeScale")
        controller.worldState.set(ReferenceEnableState(isEnabled: true), for: Self.referenceKey)
        controller.resetGlobalValue(editorID: "TimeScale")

        let snapshot = controller.runtimeStateSnapshot
        #expect(snapshot.journalTail == [
            "1 set enableState test.esm:00003F",
            "2 set global TimeScale = 120",
            "3 set enableState test.esm:00003F",
            "4 reset global TimeScale"
        ])
        #expect(snapshot.overriddenGlobalCount == 0)
        #expect(snapshot.nextJournalSequence == 5)
    }

    /// The overridden-global count is what lights the destination's override
    /// indicator for the Globals section, so it has to track the store.
    @Test @MainActor
    func snapshotReportsTheOverriddenGlobalCount() throws {
        let controller = GameViewController()
        controller.globalStore = try Self.store()
        #expect(controller.runtimeStateSnapshot.overriddenGlobalCount == 0)

        controller.setGlobalValue(120, editorID: "TimeScale")
        #expect(controller.runtimeStateSnapshot.overriddenGlobalCount == 1)

        controller.resetAllGlobalOverrides()
        #expect(controller.runtimeStateSnapshot.overriddenGlobalCount == 0)
    }

    /// The tail is bounded, and the bound applies to the merged log rather than
    /// to either ring on its own.
    @Test @MainActor
    func mergedTailIsCappedAtTheSnapshotLimit() throws {
        let controller = GameViewController()
        controller.globalStore = try Self.store()
        for step in 1 ... 6 {
            controller.worldState.set(
                ReferenceEnableState(isEnabled: step.isMultiple(of: 2)), for: Self.referenceKey
            )
            controller.setGlobalValue(Float(step), editorID: "TimeScale")
        }
        let tail = controller.runtimeStateSnapshot.journalTail
        #expect(tail.count == RuntimeStateSnapshot.journalTailLimit)
        #expect(tail.first == "5 set enableState test.esm:00003F")
        #expect(tail.last == "12 set global TimeScale = 6")
    }

    /// A short global rounds onto its declared type, and the journal line shows
    /// the stored value rather than the raw one that was asked for.
    @Test @MainActor
    func globalJournalLineShowsTheCoercedValue() throws {
        let controller = GameViewController()
        controller.globalStore = try Self.store()
        controller.setGlobalValue(3.7, editorID: "TimeScale")
        #expect(
            controller.runtimeStateSnapshot.journalTail == ["1 set global TimeScale = 4"]
        )
    }

    /// A global with no editor ID still has to be addressable in the log, so it
    /// falls back to its session-stable key.
    @Test @MainActor
    func unnamedGlobalFallsBackToItsKey() {
        let entry = WorldStateGlobalJournalEntry(
            sequence: 9,
            key: GlobalFixture.key(0x0000_003A),
            oldValue: nil,
            newValue: GlobalValue(type: .float, rawValue: 1.5)
        )
        #expect(
            GameViewController.globalJournalLine(entry, name: entry.key.description)
                == "9 set global test.esm:00003A = 1.5"
        )
    }

    // MARK: Synthetic engine state

    //
    // Invented GLOB records and an invented reference key. Nothing is read from
    // a game file.

    private static let referenceKey = ReferenceKey.plugin(name: "test.esm", objectID: 0x3F)

    private static func store() throws -> GlobalStore {
        try GlobalFixture.store(
            GlobalFixture.record(
                formID: 0x0000_003A, editorID: "TimeScale", type: .short, value: 20
            )
        )
    }
}
