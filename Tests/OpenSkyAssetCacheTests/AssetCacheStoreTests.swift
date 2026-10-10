// The cache store in a temporary folder: hits, misses, staleness, the size limit,
// clearing, and interrupted writes.

import Foundation
@testable import OpenSkyAssetCache
import Testing

struct AssetCacheStoreTests {
    private let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appending(
                path: "AssetCacheStoreTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
    }

    private func makeStore(limit: UInt64 = 1 << 30) throws -> AssetCacheStore {
        try AssetCacheStore(root: root, limitBytes: limit)
    }

    private func source(
        _ path: String = "textures\\rock.dds", size: UInt64 = 100, modified: Int64 = 1000,
        hash: UInt64 = 7
    ) -> AssetSourceStamp {
        AssetSourceStamp(
            origin: "Skyrim - Textures0.bsa",
            path: path,
            size: size,
            modified: modified,
            contentHash: hash
        )
    }

    private func request(
        _ source: AssetSourceStamp, converter: UInt32 = 1, output: UInt8 = 0,
        kind: AssetCacheKind = .texture
    ) -> AssetCacheRequest {
        AssetCacheRequest(kind: kind, source: source, converterVersion: converter, output: output)
    }

    private func payload(of lookup: AssetCacheLookup) -> Data? {
        guard case let .hit(hit) = lookup else { return nil }
        return Data(hit.payload)
    }

    @Test func aStoredEntryIsAHitWithItsPayload() throws {
        let store = try makeStore()
        try store.store(Data([1, 2, 3]), for: request(source()))
        #expect(payload(of: store.lookup(request(source()))) == Data([1, 2, 3]))
    }

    @Test func anUnknownSourceIsAMiss() throws {
        let store = try makeStore()
        guard case .miss = store.lookup(request(source())) else {
            Issue.record("expected a miss")
            return
        }
    }

    @Test(arguments: [
        (UInt64(101), Int64(1000), UInt64(7)),
        (UInt64(100), Int64(1001), UInt64(7)),
        (UInt64(100), Int64(1000), UInt64(8))
    ])
    func aChangedSourceMakesTheEntryStale(size: UInt64, modified: Int64, hash: UInt64) throws {
        let store = try makeStore()
        try store.store(Data([1]), for: request(source()))
        let changed = source(size: size, modified: modified, hash: hash)
        guard case .stale(.sourceChanged) = store.lookup(request(changed)) else {
            Issue.record("expected sourceChanged")
            return
        }
    }

    @Test func anUnknownHashDoesNotMakeTheEntryStale() throws {
        let store = try makeStore()
        try store.store(Data([1]), for: request(source()))
        #expect(payload(of: store.lookup(request(source(hash: 0)))) == Data([1]))
    }

    @Test func aNewerConverterMakesTheEntryStale() throws {
        let store = try makeStore()
        try store.store(Data([1]), for: request(source(), converter: 1))
        guard
            case .stale(.converterChanged(built: 1)) = store.lookup(request(
                source(),
                converter: 2
            ))
        else {
            Issue.record("expected converterChanged")
            return
        }
    }

    @Test func anotherTextureOutputMakesTheTextureStale() throws {
        let store = try makeStore()
        try store.store(Data([1]), for: request(source(), output: 0))
        let lookup = store.lookup(request(source(), output: 2))
        guard case .stale(.outputChanged(built: 0)) = lookup else {
            Issue.record("expected outputChanged")
            return
        }
    }

    @Test func aTextureOutputChangeLeavesMeshesCurrent() throws {
        let store = try makeStore()
        let mesh = source("meshes\\a.nif")
        try store.store(Data([1]), for: request(mesh, output: 0, kind: .mesh))
        guard case .hit = store.lookup(request(mesh, output: 2, kind: .mesh)) else {
            Issue.record("expected a mesh hit")
            return
        }
    }

    @Test func aHalfWrittenEntryIsNeverReadAsValid() throws {
        let store = try makeStore()
        let entry = request(source())
        try store.store(Data(repeating: 9, count: 64), for: entry)
        let url = store.entryURL(kind: .texture, source: entry.source)
        let whole = try Data(contentsOf: url)
        try whole.prefix(whole.count - 10).write(to: url)
        guard case .unreadable = store.lookup(entry) else {
            Issue.record("expected unreadable")
            return
        }
    }

    @Test func leftoversOfAnInterruptedWriteAreRemovedAndNotCounted() throws {
        let store = try makeStore()
        let temporary = root.appending(
            path: AssetCacheStore.temporaryFolder,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 500).write(to: temporary.appending(path: "partial"))
        #expect(store.usage().entryCount == 0)
        _ = try makeStore()
        #expect(!FileManager.default.fileExists(atPath: temporary.path(percentEncoded: false)))
    }

    @Test func entriesOfRetiredKindsAreRemovedWhenTheStoreOpens() throws {
        let store = try makeStore()
        let sound = source("sound\\fx\\a.wav")
        try store.store(Data([1, 2]), for: AssetCacheRequest(
            kind: .audio, source: sound, converterVersion: 1
        ))
        try store.store(Data([3]), for: request(source()))
        #expect(store.usage().entryCount == 2)
        let reopened = try makeStore()
        #expect(reopened.usage().entryCount == 1)
        let audioFolder = root.appending(path: "audio", directoryHint: .isDirectory)
        #expect(!FileManager.default.fileExists(atPath: audioFolder.path(percentEncoded: false)))
    }

    @Test func theLeastRecentlyUsedEntriesLeaveFirstOverTheLimit() throws {
        let store = try makeStore()
        let paths = ["a.dds", "b.dds", "c.dds"]
        for (index, path) in paths.enumerated() {
            try store.store(Data(repeating: 0, count: 1000), for: request(source(path)))
            let url = store.entryURL(kind: .texture, source: source(path))
            let date = Date(timeIntervalSince1970: TimeInterval(1000 + index))
            try FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: url.path(percentEncoded: false)
            )
        }
        // A hit makes "a" the most recently used.
        _ = store.lookup(request(source("a.dds")))
        let perEntry = store.usage().bytes / 3
        store.limitBytes = perEntry * 2
        #expect(store.enforceLimit() == 1)
        guard case .miss = store.lookup(request(source("b.dds"))) else {
            Issue.record("the oldest entry should have left")
            return
        }
        #expect(payload(of: store.lookup(request(source("a.dds")))) != nil)
        #expect(payload(of: store.lookup(request(source("c.dds")))) != nil)
    }

    @Test func aHitRefreshesAnOldUseDateButNotARecentOne() throws {
        let store = try makeStore()
        try store.store(Data([1]), for: request(source()))
        let path = store.entryURL(kind: .texture, source: source()).path(percentEncoded: false)
        func useDate() throws -> Date? {
            try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
        }
        let recent = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - 60).rounded())
        try FileManager.default.setAttributes([.modificationDate: recent], ofItemAtPath: path)
        _ = store.lookup(request(source()))
        #expect(try useDate() == recent)
        let old = Date(timeIntervalSinceNow: -7200)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: path)
        _ = store.lookup(request(source()))
        #expect(try #require(try useDate()) > Date(timeIntervalSinceNow: -60))
    }

    @Test func clearRemovesEveryEntry() throws {
        let store = try makeStore()
        try store.store(Data([1]), for: request(source("a.dds")))
        try store.store(Data([2]), for: request(source("b.dds")))
        #expect(store.usage().entryCount == 2)
        try store.clear()
        #expect(store.usage() == AssetCacheUsage(entryCount: 0, bytes: 0))
    }

    @Test func removeDeletesOneEntry() throws {
        let store = try makeStore()
        try store.store(Data([1]), for: request(source()))
        store.remove(kind: .texture, source: source())
        guard case .miss = store.lookup(request(source())) else {
            Issue.record("expected a miss")
            return
        }
    }
}
