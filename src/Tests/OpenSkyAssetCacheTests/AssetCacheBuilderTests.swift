// Background conversion over a synthetic source set: progress, resume, cancel,
// and a failing file that does not stop the run.

import Foundation
@testable import OpenSkyAssetCache
import OpenSkyGameData
import Synchronization
import Testing

private struct MemoryFiles: GameFileSource {
    let files: [String: Data]

    func exists(_ path: String) -> Bool {
        files[path] != nil
    }

    func contents(forPath path: String) throws -> Data {
        guard let data = files[path] else { throw VFSError.fileNotFound(path: path) }
        return data
    }

    func archiveEntries() -> [VFSEntry] {
        files.keys.sorted().map { VFSEntry(path: $0, archive: "test.bsa") }
    }

    func fileNames(inDirectory _: String) -> [String] {
        []
    }

    func provenance(forPath path: String) -> GameFileProvenance? {
        files[path]
            .map { GameFileProvenance(origin: "test.bsa", size: UInt64($0.count), modified: 1) }
    }
}

/// Reverses the bytes; fails on a file that starts with 0xFF; skips `.skip` files.
private struct ReversingConverter: AssetConverting {
    var kind: AssetCacheKind {
        .collision
    }

    var version: UInt32 {
        1
    }

    func accepts(path: String) -> Bool {
        path.hasSuffix(".hkx") || path.hasSuffix(".skip")
    }

    func convert(path: String, bytes: Data, output _: AssetTextureOutput) throws -> Data? {
        guard !path.hasSuffix(".skip") else { return nil }
        guard bytes.first != 0xFF else { throw CachePayloadError.badTag(0xFF) }
        return Data(bytes.reversed())
    }
}

struct AssetCacheBuilderTests {
    private let files = MemoryFiles(files: [
        "a.hkx": Data([1, 2, 3]), "b.hkx": Data([4, 5]), "bad.hkx": Data([0xFF, 0]),
        "c.skip": Data([9]), "readme.txt": Data([7])
    ])

    private func makeBuilder() throws -> AssetCacheBuilder {
        let root = FileManager.default.temporaryDirectory
            .appending(
                path: "AssetCacheBuilderTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        return try AssetCacheBuilder(
            store: AssetCacheStore(root: root, limitBytes: 1 << 30), files: files,
            converters: [ReversingConverter()]
        )
    }

    @Test func aRunConvertsReportsProgressAndSkipsAFailedFile() async throws {
        let builder = try makeBuilder()
        let items = builder.planInstall()
        #expect(items.map(\.path) == ["a.hkx", "b.hkx", "bad.hkx", "c.skip"])
        let reports = Mutex<[Int]>([])
        let result = await builder.build(items, width: 2) { progress in
            reports.withLock { $0.append(progress.doneFiles) }
        }
        #expect(result.isFinished)
        #expect(result.converted == 2)
        #expect(result.notStored == 1)
        #expect(result.failures.map(\.path) == ["bad.hkx"])
        #expect(result.totalBytes == 8)
        #expect(reports.withLock { $0.sorted() } == [1, 2, 3, 4])
    }

    @Test func aSecondRunResumesAndSkipsCurrentEntries() async throws {
        let builder = try makeBuilder()
        _ = await builder.build(builder.planInstall())
        let second = await builder.build(builder.planInstall())
        #expect(second.converted == 0)
        #expect(second.alreadyCurrent == 3)
    }

    @Test func cancellingStopsTheRunAndALaterRunFinishesIt() async throws {
        let builder = try makeBuilder()
        let items = builder.planInstall()
        let control = AssetCacheBuildControl()
        let cancelled = await builder.build(items, width: 1, control: control) { progress in
            if progress.doneFiles == 1 {
                control.cancel()
            }
        }
        #expect(cancelled.isCancelled)
        #expect(cancelled.doneFiles < items.count)
        let resumed = await builder.build(items)
        #expect(resumed.alreadyCurrent == cancelled.converted)
        #expect(resumed.converted + resumed.alreadyCurrent == 2)
    }

    @Test func theTimeLeftFollowsTheByteRate() {
        var progress = AssetCacheBuildProgress()
        progress.totalBytes = 100
        progress.doneBytes = 25
        progress.elapsedSeconds = 5
        #expect(progress.estimatedSecondsLeft == 15)
    }

    @Test func aCheckCountsCurrentStaleAndMissingEntries() async throws {
        let builder = try makeBuilder()
        let items = builder.planInstall()
        #expect(await builder.check(items).summary == .notBuilt)
        _ = await builder.build(items)
        let built = await builder.check(items)
        #expect(built.kinds[.collision] == AssetCacheKindCheck(
            current: 3, stale: 0, missing: 1, pendingSourceBytes: 2
        ))
        #expect(built.summary == .partlyBuilt)
        // A texture output change leaves the other kinds current.
        let other = AssetCacheBuilder(
            store: builder.store, files: files, converters: [ReversingConverter()],
            textureOutput: AssetTextureOutput(quality: .medium)
        )
        #expect(await other.check(items).summary == .partlyBuilt)
    }

    @Test func theThrottleLetsTheFirstAndTheFinalReportThrough() {
        let throttle = AssetCacheProgressThrottle(interval: .seconds(60))
        var progress = AssetCacheBuildProgress()
        progress.totalFiles = 2
        progress.doneFiles = 1
        #expect(throttle.shouldReport(progress))
        #expect(!throttle.shouldReport(progress))
        progress.doneFiles = 2
        #expect(throttle.shouldReport(progress))
    }
}
