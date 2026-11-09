// The save world names slots, maps file errors to save failures, and guards Skyrim imports.

import Foundation
import OpenSkyGameData
import OpenSkySessionAdapters
import OpenSkySessionTesting
import Testing

@MainActor
struct SaveGameWorldTests {
    private let host = SessionHost()

    @Test func aNewSlotSkipsTakenNames() {
        #expect(SaveGameWorldAdapter.newSlotName(existing: []) == "Save 1")
        #expect(SaveGameWorldAdapter.newSlotName(existing: ["Save 2"]) == "Save 3")
    }

    @Test func fileErrorsBecomeSaveFailures() {
        let full = SaveGameWorldAdapter.failure(CocoaError(.fileWriteOutOfSpace))
        let posix = SaveGameWorldAdapter.failure(POSIXError(.ENOSPC))
        let missing = SaveGameWorldAdapter.failure(CocoaError(.fileReadNoSuchFile))
        let device = SaveGameWorldAdapter.failure(CocoaError(.fileReadNoPermission))
        #expect(full as? SaveFailure == .outOfDiskSpace)
        #expect(posix as? SaveFailure == .outOfDiskSpace)
        #expect(missing as? SaveFailure == .fileNotFound)
        #expect(device as? SaveFailure == .deviceError)
        #expect(SaveGameWorldAdapter.failure(SaveFailure.corrupt) as? SaveFailure == .corrupt)
    }

    @Test func aSkyrimSaveHasAnImportSlot() {
        let slot = SkyrimSaveImport.slot(for: URL(filePath: "/saves/a.ess"))
        #expect(SkyrimSaveImport.isImport(slot))
        #expect(!SkyrimSaveImport.isImport("Save 1"))
    }

    @Test func withoutScriptsOrDataSavingIsOpenWithVanillaTexts() {
        let saves = SaveGameWorldAdapter(
            game: host,
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        #expect(!saves.isSavingDisabled)
        #expect(saves.saveTexts == .vanilla)
        saves.resetPlayTime()
        #expect(saves.lastSaveDate == nil)
        #expect(saves.saveRows.isEmpty)
    }

    @Test func deletingAnImportedSaveDoesNothing() async throws {
        let saves = SaveGameWorldAdapter(
            game: host,
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        let slot = SkyrimSaveImport.slot(for: URL(filePath: "/saves/a.ess"))
        try await saves.deleteSave(slot: slot)
        #expect(host.fakeRuntimeStateWorld.deleteSaveCalls.isEmpty)
    }
}
