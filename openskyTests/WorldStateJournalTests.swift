// WorldStateStore journal, snapshot and generated-key tests (issue #159),
// split from WorldStateStoreTests to stay inside the type-body length limit.
//
// The store is @MainActor, so the suite is too. Fixtures are synthetic and
// built in code.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct WorldStateJournalTests {
    // MARK: - Fixtures

    private let whiterun = CellSceneLocation.exterior(CellCoordinate(x: 5, y: -1))
    private let riverwood = CellSceneLocation.exterior(CellCoordinate(x: 6, y: -1))
    private let inn = CellSceneLocation.interior(FormID(0x1234))

    private func key(_ objectID: UInt32, plugin: String = "skyrim.esm") -> ReferenceKey {
        .plugin(name: plugin, objectID: objectID)
    }

    private func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    private func referenceEntry(objectID: UInt32 = 0x200) throws -> RuntimeReferenceEntry {
        var name = Data()
        name.appendUInt32(0x100)
        var data = Data()
        for value in [Float(1), 2, 3, 0, 0, 0] {
            data.appendFloat32(value)
        }
        var scale = Data()
        scale.appendFloat32(2)
        let fields = ESMFixture.field("NAME", name)
            + ESMFixture.field("DATA", data)
            + ESMFixture.field("XSCL", scale)
        let bytes = ESMFixture.record("REFR", formID: objectID, data: fields)
        return try RuntimeReferenceEntry(
            key: key(objectID),
            formID: FormID(objectID),
            isPersistent: false,
            record: .reference(PlacedReference(record: record(bytes)))
        )
    }

    private func transform(_ x: Float) -> ReferenceTransformOverride {
        ReferenceTransformOverride(position: SIMD3(x, 0, 0), scale: 1)
    }

    // MARK: - Journal

    @Test func journalRecordsOrderSequenceAndValues() {
        let store = WorldStateStore()
        let reference = key(0x200)
        store.set(ReferenceEnableState.disabled, for: reference, in: whiterun)
        store.set(ReferenceEnableState.enabled, for: reference, in: whiterun)
        store.reset(.enableState, for: reference)

        let entries = store.journalEntries
        #expect(entries.count == 3)
        #expect(entries.map(\.sequence) == [1, 2, 3])
        #expect(entries.allSatisfy { $0.key == reference && $0.kind == .enableState })
        #expect(entries.allSatisfy { $0.cell == whiterun })
        #expect(entries[0].oldValue == nil)
        #expect(entries[0].newValue == .enableState(.disabled))
        #expect(entries[1].oldValue == .enableState(.disabled))
        #expect(entries[1].newValue == .enableState(.enabled))
        #expect(entries[2].oldValue == .enableState(.enabled))
        #expect(entries[2].newValue == nil)
        #expect(entries[2].isReset)
        #expect(store.nextJournalSequence == 4)
        #expect(store.droppedJournalEntryCount == 0)
    }

    @Test func journalDropsOldestEntriesPastItsCap() {
        let store = WorldStateStore(journalCapacity: 4)
        for step in 0 ..< 10 {
            store.set(transform(Float(step)), for: key(0x200), in: whiterun)
        }
        #expect(store.journalCapacity == 4)
        #expect(store.journalEntries.count == 4)
        #expect(store.journalEntries.map(\.sequence) == [7, 8, 9, 10])
        #expect(store.droppedJournalEntryCount == 6)
        #expect(store.nextJournalSequence == 11)
        // State itself is untouched by the window sliding.
        #expect(store.component(ReferenceTransformOverride.self, for: key(0x200)) == transform(9))
    }

    @Test func journalDefaultCapacityIsTheDocumentedCap() {
        #expect(WorldStateJournal.defaultCapacity == 4096)
        #expect(WorldStateStore().journalCapacity == 4096)
        // A nonsensical cap is clamped rather than rejected: journalling must
        // never be the thing that fails a mutation.
        let clamped = WorldStateStore(journalCapacity: 0)
        clamped.set(ReferenceEnableState.disabled, for: key(0x200))
        #expect(clamped.journalCapacity == 1)
        #expect(clamped.journalEntries.count == 1)
    }

    @Test func journalQueriesSinceASequenceAndClears() {
        let store = WorldStateStore()
        store.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun)
        store.set(transform(1), for: key(0x201), in: whiterun)
        store.set(ReferenceDeletionState.deleted, for: key(0x202), in: riverwood)
        #expect(store.journalEntries(since: 2).map(\.sequence) == [2, 3])
        store.clearJournal()
        #expect(store.journalEntries.isEmpty)
        // Clearing the window does not claim the mutations never happened.
        #expect(store.nextJournalSequence == 4)
        #expect(store.dirtyCount == 3)
    }

    // MARK: - Snapshot

    @Test func snapshotOrdersEntriesByReferenceKeyTotalOrder() {
        let store = WorldStateStore()
        store.set(transform(1), for: .generated(2), in: whiterun)
        store.set(transform(2), for: key(0x202, plugin: "update.esm"), in: whiterun)
        store.set(transform(3), for: .generated(1), in: whiterun)
        store.set(transform(4), for: key(0x201), in: whiterun)
        store.set(transform(5), for: key(0x200), in: whiterun)

        let snapshot = store.snapshot()
        #expect(snapshot.keys == [
            key(0x200),
            key(0x201),
            key(0x202, plugin: "update.esm"),
            .generated(1),
            .generated(2)
        ])
        #expect(snapshot.dirtyCount == 5)
        #expect(snapshot.dirtyCount(in: whiterun) == 5)
        #expect(snapshot[key(0x201)]?.component(ReferenceTransformOverride.self) == transform(4))
    }

    @Test func snapshotsAreEqualForTheSameEndStateRegardlessOfMutationOrder() {
        let first = WorldStateStore()
        first.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun)
        first.set(transform(7), for: key(0x201), in: riverwood)
        first.set(ReferenceActivationState(activationCount: 3), for: key(0x200), in: whiterun)
        first.set(ReferenceDeletionState.deleted, for: key(0x202), in: riverwood)
        first.reset(key(0x202))

        let second = WorldStateStore(journalCapacity: 16)
        second.set(ReferenceActivationState(activationCount: 9), for: key(0x200), in: inn)
        second.set(transform(7), for: key(0x201), in: riverwood)
        second.set(ReferenceActivationState(activationCount: 3), for: key(0x200), in: whiterun)
        second.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun)

        #expect(first.snapshot() == second.snapshot())
        // The journals differ even though the end states match, which is the
        // point of keeping them separate products.
        #expect(first.journalEntries.count != second.journalEntries.count)
    }

    @Test func snapshotIsAnImmutableCopy() {
        let store = WorldStateStore()
        store.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun)
        let snapshot = store.snapshot()
        store.set(transform(1), for: key(0x201), in: whiterun)
        store.reset(key(0x200))
        #expect(snapshot.dirtyCount == 1)
        #expect(snapshot.keys == [key(0x200)])
        #expect(store.snapshot().keys == [key(0x201)])
    }

    @Test func snapshotResolvesStateAgainstALiveRecord() throws {
        let store = WorldStateStore()
        let entry = try referenceEntry()
        store.set(ReferenceEnableState.disabled, for: entry.key, in: whiterun)
        let snapshot = store.snapshot()
        let resolved = snapshot.resolvedState(for: entry)
        #expect(resolved.enableState == .disabled)
        // Untouched slots still come from the record, never from a cached copy.
        #expect(resolved.transform.position == SIMD3(1, 2, 3))
        #expect(resolved.transform.scale == 2)
        #expect(snapshot.entries(in: whiterun).map(\.key) == [entry.key])
    }

    // MARK: - Generated references

    @Test func allocatesGeneratedKeysThroughTheStore() {
        let store = WorldStateStore()
        #expect(store.nextGeneratedSequence == 1)
        #expect(store.allocateGeneratedKey() == .generated(1))
        #expect(store.allocateGeneratedKey() == .generated(2))
        #expect(store.nextGeneratedSequence == 3)
        #expect(store.snapshot().nextGeneratedSequence == 3)

        // A restored session resumes where the saved allocator left off.
        let restored = WorldStateStore(allocator: GeneratedReferenceAllocator(nextSequence: 42))
        #expect(restored.allocateGeneratedKey() == .generated(42))
    }

    @Test func generatedAllocationCountsTowardSnapshotEquality() {
        let first = WorldStateStore()
        let second = WorldStateStore()
        #expect(first.snapshot() == second.snapshot())
        _ = first.allocateGeneratedKey()
        #expect(first.snapshot() != second.snapshot())
        _ = second.allocateGeneratedKey()
        #expect(first.snapshot() == second.snapshot())
    }

    @Test func activationStateAdvancesThroughItsHelper() {
        let store = WorldStateStore()
        let door = key(0x200)
        let player = key(0x14)
        let opened = ReferenceActivationState.untouched.activated(by: player, togglesOpen: true)
        store.set(opened, for: door, in: inn)
        #expect(opened.activationCount == 1)
        #expect(opened.isOpen)
        #expect(opened.wasActivated)
        let closed = opened.activated(by: player, togglesOpen: true)
        store.set(closed, for: door, in: inn)
        #expect(closed.activationCount == 2)
        #expect(closed.isOpen == false)
        #expect(store.component(ReferenceActivationState.self, for: door) == closed)
        #expect(store.journalEntries.count == 2)
    }
}
