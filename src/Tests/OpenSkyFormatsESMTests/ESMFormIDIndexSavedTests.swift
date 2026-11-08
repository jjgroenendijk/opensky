// A saved FormID index must read back as the index a walk builds, and a copy that
// does not fit the plugin must be refused, so the caller walks the plugin again.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyTagsTesting
import Synchronization
import Testing

@Suite(.tags(.parser))
struct ESMFormIDIndexSavedTests {
    private final class MemoryStore: FormIDIndexStore {
        let indexes = Mutex<[ESMFileStamp: Data]>([:])

        func savedIndex(for stamp: ESMFileStamp) -> Data? {
            indexes.withLock { $0[stamp] }
        }

        func save(_ index: Data, for stamp: ESMFileStamp) {
            indexes.withLock { $0[stamp] = index }
        }
    }

    private static let formIDs: [UInt32] = [0x1A, 0x2B, 0x3C, 0x50]

    @Test func aSavedIndexReadsBackAsTheWalkedOne() throws {
        let file = try ESMFormIDIndexTests.plugin()
        let walked = ESMFormIDIndex(file: file)
        let read = try #require(ESMFormIDIndex(file: file, saved: walked.saved()))
        #expect(read.count == walked.count)
        for formID in Self.formIDs {
            #expect(read.record(withFormID: formID)?.dataRange
                == walked.record(withFormID: formID)?.dataRange)
            #expect(read.cellFormID(containing: formID) == walked.cellFormID(containing: formID))
            #expect(read.worldFormID(containing: formID) == walked.worldFormID(containing: formID))
        }
    }

    @Test func aCopyThatDoesNotFitIsRefused() throws {
        let file = try ESMFormIDIndexTests.plugin()
        let saved = ESMFormIDIndex(file: file).saved()
        #expect(ESMFormIDIndex(file: file, saved: saved.dropLast()) == nil)
        var badMagic = saved
        badMagic[0] ^= 0xFF
        #expect(ESMFormIDIndex(file: file, saved: badMagic) == nil)
        var farOffset = saved
        farOffset.replaceSubrange(16 ..< 20, with: [0xFF, 0xFF, 0xFF, 0x7F])
        #expect(ESMFormIDIndex(file: file, saved: farOffset) == nil)
    }

    @Test func loadingSavesOnceAndThenReadsTheCopy() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "ESMFormIDIndexSavedTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Mod.esp")
        try ESMFormIDIndexTests.plugin().data.write(to: url)
        let file = try ESMFile(url: url)
        let stamp = try #require(file.stamp)
        let store = MemoryStore()
        let first = ESMFormIDIndex.loading(file: file, store: store)
        let saved = try #require(store.savedIndex(for: stamp))
        let second = ESMFormIDIndex.loading(file: file, store: store)
        #expect(store.savedIndex(for: stamp) == saved)
        #expect(second.count == first.count)
        #expect(second.record(withFormID: 0x3C)?.type == "REFR")
    }
}
