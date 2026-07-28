// WorldStateStore.restore(from:) tests (issue #162, roadmap item 10.1.5): the
// path a decoded save takes back into a live store.
//
// Fixtures come from OpenSkySaveFixture, so the state being restored is the
// same rich snapshot the container round-trip tests use. Nothing here reads a
// file or touches game data.

@testable import opensky
import Testing

@MainActor
struct WorldStateStoreRestoreTests {
    private static let key = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x4321)

    @Test
    func restoreIntoAFreshStoreReproducesTheSnapshot() {
        let snapshot = OpenSkySaveFixture.richSnapshot()
        let store = WorldStateStore()

        store.restore(from: snapshot)

        #expect(store.snapshot() == snapshot)
        #expect(store.dirtyCount == snapshot.entries.count)
    }

    @Test
    func restoreAdoptsTheAllocatorPosition() {
        let store = WorldStateStore()

        store.restore(from: OpenSkySaveFixture.richSnapshot(nextGeneratedSequence: 500))

        #expect(store.nextGeneratedSequence == 500)
        #expect(store.allocateGeneratedKey() == .generated(500))
        #expect(store.allocateGeneratedKey() == .generated(501))
        #expect(store.nextGeneratedSequence == 502)
    }

    @Test
    func restoreReplacesExistingState() {
        let store = WorldStateStore()
        store.set(ReferenceEnableState.disabled, for: Self.key, in: OpenSkySaveFixture.whiterun)
        #expect(store.isDirty(Self.key))

        let snapshot = OpenSkySaveFixture.richSnapshot()
        store.restore(from: snapshot)

        #expect(!store.isDirty(Self.key))
        #expect(store.snapshot() == snapshot)
    }

    @Test
    func restoreOfTheEmptySnapshotClearsTheStore() {
        let store = WorldStateStore()
        store.set(ReferenceEnableState.disabled, for: Self.key, in: OpenSkySaveFixture.whiterun)

        store.restore(from: .empty)

        #expect(store.dirtyCount == 0)
        #expect(store.snapshot() == .empty)
        #expect(store.dirtyCountsByCellLocation.isEmpty)
    }

    @Test
    func restoreRebuildsPerCellDirtyCounts() {
        let store = WorldStateStore()

        store.restore(from: OpenSkySaveFixture.richSnapshot())

        // The rich snapshot places one entry in Whiterun, one in the inn, one
        // in Riverwood and one with no cell at all.
        #expect(store.dirtyCount(in: OpenSkySaveFixture.whiterun) == 1)
        #expect(store.dirtyCount(in: OpenSkySaveFixture.riverwood) == 1)
        #expect(store.dirtyCount(in: OpenSkySaveFixture.inn) == 1)
        #expect(store.unattributedDirtyCount == 1)
    }

    @Test
    func restoreJournalsNothingAndClearsTheRetainedWindow() {
        let store = WorldStateStore()
        store.set(ReferenceEnableState.disabled, for: Self.key, in: OpenSkySaveFixture.whiterun)
        let sequenceBefore = store.nextJournalSequence

        store.restore(from: OpenSkySaveFixture.richSnapshot())

        #expect(store.journalEntries.isEmpty)
        #expect(store.nextJournalSequence == sequenceBefore)
    }

    @Test
    func restoreAnnouncesOneUnattributedMutation() {
        let store = WorldStateStore()
        var announced: [(CellSceneLocation?, UInt64)] = []
        store.onMutation = { location, sequence in
            announced.append((location, sequence))
        }

        store.restore(from: OpenSkySaveFixture.richSnapshot())

        #expect(announced.count == 1)
        #expect(announced.first?.0 == nil)
        #expect(announced.first?.1 == store.nextJournalSequence)
    }
}
