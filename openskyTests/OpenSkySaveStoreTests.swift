// OpenSkySaveStore tests (issue #162, roadmap item 10.1.5): slot naming, the
// save-then-load round trip, listing, and every failure the slot layer reports.
//
// Files are written to a per-test temporary directory that is removed again at
// the end of the test. Save bytes come from the synthetic OpenSkySaveFixture
// state and plugin bytes from ESMFixture, so no game data is involved.

import Foundation
@testable import opensky
import Testing

struct OpenSkySaveStoreTests {
    // MARK: - Fixtures

    /// Runs `body` against a store rooted at a fresh temporary directory and
    /// removes the directory afterwards, including when `body` throws.
    private func withTemporaryStore(_ body: (OpenSkySaveStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "opensky-save-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(OpenSkySaveStore(directory: directory))
    }

    @discardableResult
    private func save(
        _ store: OpenSkySaveStore,
        slot: String,
        snapshot: WorldStateSnapshot = OpenSkySaveFixture.richSnapshot()
    ) throws -> URL {
        try store.save(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            toSlot: slot
        )
    }

    // MARK: - Round trip

    @Test
    func savingThenLoadingReproducesTheSnapshotAndAllocator() throws {
        try withTemporaryStore { store in
            let snapshot = OpenSkySaveFixture.richSnapshot(nextGeneratedSequence: 91)
            let written = try save(store, slot: "quicksave", snapshot: snapshot)
            #expect(written.lastPathComponent == "quicksave.osav")

            let file = try store.load(slot: "quicksave")

            #expect(file.snapshot == snapshot)
            #expect(file.allocator.nextSequence == 91)
            #expect(file.metadata == OpenSkySaveFixture.metadata)
            #expect(file.fingerprint == OpenSkySaveFixture.fingerprint)
        }
    }

    @Test
    func savingTwiceToOneSlotKeepsTheNewerState() throws {
        try withTemporaryStore { store in
            try save(store, slot: "slot1", snapshot: .empty)
            let second = OpenSkySaveFixture.richSnapshot(nextGeneratedSequence: 3)
            try save(store, slot: "slot1", snapshot: second)

            #expect(try store.load(slot: "slot1").snapshot == second)
            #expect(try store.listSlots() == ["slot1"])
        }
    }

    @Test
    func listSlotsReportsSavedSlotsSortedAndWithoutTheExtension() throws {
        try withTemporaryStore { store in
            #expect(try store.listSlots().isEmpty)
            try save(store, slot: "zulu")
            try save(store, slot: "alpha")

            #expect(try store.listSlots() == ["alpha", "zulu"])
        }
    }

    @Test
    func listSlotsIgnoresFilesThatAreNotSaves() throws {
        try withTemporaryStore { store in
            try save(store, slot: "real")
            let stray = store.directory.appending(path: "notes.txt", directoryHint: .notDirectory)
            try Data("hello".utf8).write(to: stray)

            #expect(try store.listSlots() == ["real"])
        }
    }

    @Test
    func listSlotsOnAMissingDirectoryIsEmptyRatherThanAFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "opensky-absent-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = OpenSkySaveStore(directory: directory)

        #expect(try store.listSlots().isEmpty)
    }

    // MARK: - Slot names

    @Test(arguments: [
        "",
        "saves/escape",
        "../escape",
        "volume:name",
        "back\\slash",
        ".hidden",
        "bell\u{7}"
    ])
    func invalidSlotNamesThrow(_ slot: String) throws {
        try withTemporaryStore { store in
            #expect(throws: OpenSkySaveStoreError.self) {
                try store.url(forSlot: slot)
            }
        }
    }

    @Test
    func anOverLongSlotNameThrows() throws {
        try withTemporaryStore { store in
            let slot = String(repeating: "a", count: OpenSkySaveStore.maximumSlotNameLength + 1)
            #expect(throws: OpenSkySaveStoreError.self) {
                try store.url(forSlot: slot)
            }
        }
    }

    @Test
    func ordinarySlotNamesAreAccepted() throws {
        try withTemporaryStore { store in
            let url = try store.url(forSlot: "Save 3 — Riverwood")
            #expect(url.lastPathComponent == "Save 3 — Riverwood.osav")
            #expect(url.deletingLastPathComponent() == store.directory)
        }
    }

    // MARK: - Failures

    @Test
    func loadingAMissingSlotThrowsSlotNotFound() throws {
        try withTemporaryStore { store in
            #expect(throws: OpenSkySaveStoreError.slotNotFound("nothing")) {
                try store.load(slot: "nothing")
            }
        }
    }

    @Test
    func loadingACorruptFileSurfacesTheContainerError() throws {
        try withTemporaryStore { store in
            let destination = try store.url(forSlot: "corrupt")
            try Data("not a save at all".utf8).write(to: destination)

            #expect(throws: OpenSkySaveError.badMagic) {
                try store.load(slot: "corrupt")
            }
        }
    }

    @Test
    func loadingWithAChangedLoadOrderReportsAFingerprintMismatch() throws {
        try withTemporaryStore { store in
            try save(store, slot: "quicksave")
            let installed = [
                SavePluginFingerprint(
                    name: "Skyrim.esm",
                    hedrVersion: 1.71,
                    recordCount: 999,
                    nextObjectID: 0x0010_0000
                )
            ]

            #expect(throws: OpenSkySaveError.self) {
                try store.load(slot: "quicksave", verifyingAgainst: installed)
            }
            // The same file loads without verification, because decoding must
            // work with nothing but the file.
            #expect(try store.load(slot: "quicksave").fingerprint.count == 2)
        }
    }

    @Test
    func loadingWithAMatchingLoadOrderVerifies() throws {
        try withTemporaryStore { store in
            try save(store, slot: "quicksave")
            let file = try store.load(
                slot: "quicksave",
                verifyingAgainst: OpenSkySaveFixture.fingerprint
            )
            #expect(file.fingerprint == OpenSkySaveFixture.fingerprint)
        }
    }
}
