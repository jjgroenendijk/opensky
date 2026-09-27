// Runtime global-variable layer in WorldStateStore (issue #165): typed
// mutation and its rounding, reset to plugin default, the change journal, the
// snapshot, and restore. See docs/engine/runtime-state.md.

import Foundation
@testable import opensky
import Testing

@MainActor
struct WorldStateGlobalsTests {
    @Test func setsAndReadsAnOverride() {
        let store = WorldStateStore()
        let key = GlobalFixture.key(0x0800)
        #expect(store.globalValue(for: key) == nil)
        #expect(store.setGlobal(2.5, type: .float, for: key))
        #expect(store.globalValue(for: key) == GlobalValue(type: .float, rawValue: 2.5))
        #expect(store.overriddenGlobalCount == 1)
        // Reference deltas are a separate map and stay untouched.
        #expect(store.dirtyCount == 0)
    }

    @Test func repeatedIdenticalWriteIsNoOp() {
        let store = WorldStateStore()
        let key = GlobalFixture.key(0x0800)
        #expect(store.setGlobal(4, type: .short, for: key))
        #expect(!store.setGlobal(4, type: .short, for: key))
        // 4.2 rounds onto 4 for a short, so it is the same stored value.
        #expect(!store.setGlobal(4.2, type: .short, for: key))
        #expect(store.globalJournalEntries.count == 1)
    }

    /// Short and long mutations round-trip as integers; float passes through.
    @Test func integerTypesRoundOnWrite() {
        let store = WorldStateStore()
        let short = GlobalFixture.key(0x0801)
        let long = GlobalFixture.key(0x0802)
        let float = GlobalFixture.key(0x0803)
        store.setGlobal(3.7, type: .short, for: short)
        store.setGlobal(-2.5, type: .long, for: long)
        store.setGlobal(3.7, type: .float, for: float)
        #expect(store.globalValue(for: short)?.value == 4)
        #expect(store.globalValue(for: short)?.integerValue == 4)
        #expect(store.globalValue(for: long)?.value == -3)
        #expect(store.globalValue(for: float)?.value == 3.7)
    }

    @Test func resetRemovesTheOverride() {
        let store = WorldStateStore()
        let key = GlobalFixture.key(0x0800)
        #expect(!store.resetGlobal(for: key))
        store.setGlobal(9, type: .short, for: key)
        #expect(store.resetGlobal(for: key))
        #expect(store.globalValue(for: key) == nil)
        #expect(store.overriddenGlobalCount == 0)
        // An empty delta means nothing to snapshot and nothing to save.
        #expect(store.snapshot().globals.isEmpty)
    }

    @Test func resetAllClearsInKeyOrder() {
        let store = WorldStateStore()
        store.setGlobal(1, type: .short, for: GlobalFixture.key(0x0802))
        store.setGlobal(2, type: .short, for: GlobalFixture.key(0x0800))
        store.resetAllGlobals()
        #expect(store.overriddenGlobalCount == 0)
        let resets = store.globalJournalEntries.filter(\.isReset).map(\.key)
        #expect(resets == [GlobalFixture.key(0x0800), GlobalFixture.key(0x0802)])
    }

    // MARK: - Journal

    @Test func journalRecordsOldAndNewValues() {
        let store = WorldStateStore()
        let key = GlobalFixture.key(0x0800)
        store.setGlobal(1, type: .short, for: key)
        store.setGlobal(2, type: .short, for: key)
        store.resetGlobal(for: key)
        let entries = store.globalJournalEntries
        #expect(entries.count == 3)
        #expect(entries[0].oldValue == nil)
        #expect(entries[0].newValue == GlobalValue(type: .short, rawValue: 1))
        #expect(entries[1].oldValue == GlobalValue(type: .short, rawValue: 1))
        #expect(entries[2].isReset)
        #expect(entries[2].newValue == nil)
        #expect(entries.map(\.sequence) == [1, 2, 3])
    }

    /// The two journals share one counter, so interleaving by sequence
    /// reproduces the real order.
    @Test func globalAndComponentJournalsShareSequence() {
        let store = WorldStateStore()
        let reference = ReferenceKey.plugin(name: "test.esm", objectID: 1)
        store.set(ReferenceEnableState(isEnabled: false), for: reference)
        store.setGlobal(1, type: .short, for: GlobalFixture.key(0x0800))
        store.set(ReferenceEnableState(isEnabled: true), for: reference)
        #expect(store.journalEntries.map(\.sequence) == [1, 3])
        #expect(store.globalJournalEntries.map(\.sequence) == [2])
        #expect(store.nextJournalSequence == 4)
        #expect(store.droppedGlobalJournalEntryCount == 0)
    }

    @Test func journalWindowIsBounded() {
        let store = WorldStateStore(journalCapacity: 2)
        let key = GlobalFixture.key(0x0800)
        for value in 1 ... 5 {
            store.setGlobal(Float(value), type: .short, for: key)
        }
        #expect(store.globalJournalEntries.count == 2)
        #expect(store.droppedGlobalJournalEntryCount == 3)
        #expect(store.globalJournalEntries.map(\.sequence) == [4, 5])
    }

    // MARK: - Callbacks

    /// A global changes a number, not a scene, so it must not drive cell
    /// rebuilds through `onMutation`.
    @Test func globalWritesFireOnlyTheGlobalCallback() {
        let store = WorldStateStore()
        var cellRebuilds = 0
        var globalNotices: [UInt64] = []
        store.onMutation = { _, _ in cellRebuilds += 1 }
        store.onGlobalMutation = { globalNotices.append($0) }
        store.setGlobal(1, type: .short, for: GlobalFixture.key(0x0800))
        store.resetGlobal(for: GlobalFixture.key(0x0800))
        #expect(cellRebuilds == 0)
        #expect(globalNotices == [2, 3])
    }

    // MARK: - Snapshot and restore

    @Test func snapshotOrdersGlobalsByKey() {
        let store = WorldStateStore()
        store.setGlobal(3, type: .short, for: GlobalFixture.key(0x0802))
        store.setGlobal(1, type: .float, for: GlobalFixture.key(0x0800))
        let snapshot = store.snapshot()
        #expect(snapshot.globals.map(\.key)
            == [GlobalFixture.key(0x0800), GlobalFixture.key(0x0802)])
        #expect(snapshot.dirtyGlobalCount == 2)
        #expect(snapshot.globalValue(for: GlobalFixture.key(0x0800))?.value == 1)
        #expect(!snapshot.isEmpty)
    }

    @Test func snapshotEqualityCoversGlobals() {
        let store = WorldStateStore()
        let base = store.snapshot()
        store.setGlobal(1, type: .short, for: GlobalFixture.key(0x0800))
        #expect(store.snapshot() != base)
        store.resetGlobal(for: GlobalFixture.key(0x0800))
        // Sequence advanced but the end state is the same, and sequence is
        // deliberately outside equality.
        #expect(store.snapshot() == base)
    }

    @Test func restoreReplacesGlobals() {
        let store = WorldStateStore()
        store.setGlobal(5, type: .short, for: GlobalFixture.key(0x0800))
        let saved = store.snapshot()
        store.resetAllGlobals()
        store.setGlobal(9, type: .float, for: GlobalFixture.key(0x0900))
        store.restore(from: saved)
        #expect(store.snapshot() == saved)
        #expect(store.globalValue(for: GlobalFixture.key(0x0900)) == nil)
        #expect(store.globalJournalEntries.isEmpty)
    }

    // MARK: - Store-backed convenience

    @Test func setGlobalThroughTheDefaultsStore() throws {
        let records = GlobalFixture.record(
            formID: 0x0100_0800, editorID: "ShortGlobal", type: .short, value: 1
        )
        let defaults = try GlobalFixture.store(records)
        let store = WorldStateStore()
        #expect(store.setGlobal(6.6, formID: FormID(0x0100_0800), defaults: defaults))
        // Declared type came from the record: 6.6 rounds to 7.
        #expect(store.globalValue(for: GlobalFixture.key(0x0800))?.value == 7)
        #expect(store.globalResolution(defaults: defaults)
            .floatValue(editorID: "ShortGlobal") == 7)
        // A FormID the plugin does not define is reported, not invented.
        #expect(!store.setGlobal(1, formID: FormID(0xDEAD), defaults: defaults))
    }
}
