// Builds the cache for a set of source paths in the background. It runs as a
// `@concurrent` function with one child task per core at the caller's low
// priority, skips entries that are already current (so a later run resumes),
// reports progress after every file, and records a failed file without stopping.

import Foundation
import OpenSkyGameData
import Synchronization

nonisolated public struct AssetCacheBuildItem: Sendable {
    public let path: String
    public let converter: any AssetConverting

    public init(path: String, converter: any AssetConverting) {
        self.path = path
        self.converter = converter
    }
}

nonisolated public struct AssetCacheBuildFailure: Equatable, Sendable {
    public let path: String
    public let kind: AssetCacheKind
    public let reason: String
}

nonisolated public struct AssetCacheBuildProgress: Equatable, Sendable {
    public var totalFiles = 0
    public var doneFiles = 0
    public var totalBytes: UInt64 = 0
    public var doneBytes: UInt64 = 0
    /// Entries written by this run.
    public var converted = 0
    /// Entries that were current already.
    public var alreadyCurrent = 0
    /// Sources a converter does not store; they load from the original file.
    public var notStored = 0
    public var failures: [AssetCacheBuildFailure] = []
    public var elapsedSeconds: Double = 0
    public var isCancelled = false

    public init() {}

    public var isFinished: Bool {
        doneFiles == totalFiles
    }

    /// From the bytes done so far; nil before any byte is done.
    public var estimatedSecondsLeft: Double? {
        guard doneBytes > 0, elapsedSeconds > 0 else { return nil }
        let rate = Double(doneBytes) / elapsedSeconds
        return Double(totalBytes - min(totalBytes, doneBytes)) / rate
    }
}

/// Cancels a running build from any thread, such as a Cancel button.
nonisolated public final class AssetCacheBuildControl: Sendable {
    private let cancelled = Atomic<Bool>(false)

    public init() {}

    public func cancel() {
        cancelled.store(true, ordering: .relaxed)
    }

    public var isCancelled: Bool {
        cancelled.load(ordering: .relaxed) || Task.isCancelled
    }
}

nonisolated public final class AssetCacheBuilder: Sendable {
    public let store: AssetCacheStore
    let files: any GameFileSource
    private let converters: [any AssetConverting]
    public let textureOutput: AssetTextureOutput

    public init(
        store: AssetCacheStore, files: any GameFileSource, converters: [any AssetConverting],
        textureOutput: AssetTextureOutput = AssetTextureOutput()
    ) {
        self.store = store
        self.files = files
        self.converters = converters
        self.textureOutput = textureOutput
    }

    /// One item per path and converter that accepts it, in path order.
    public func plan(paths: [String]) -> [AssetCacheBuildItem] {
        paths.sorted().flatMap { path in
            let key = (try? VirtualFileSystem.normalize(path)) ?? path
            return converters.filter { $0.accepts(path: key) }
                .map { AssetCacheBuildItem(path: key, converter: $0) }
        }
    }

    /// Every archive path of the install.
    public func planInstall() -> [AssetCacheBuildItem] {
        plan(paths: files.archiveEntries().map(\.path))
    }

    /// Runs `items` with `width` workers. Cancelling the task or `control` stops
    /// after the files in flight; the result says so.
    @concurrent
    public func build(
        _ items: [AssetCacheBuildItem],
        width: Int = ProcessInfo.processInfo.activeProcessorCount,
        control: AssetCacheBuildControl = AssetCacheBuildControl(),
        progress report: @escaping @Sendable (AssetCacheBuildProgress) -> Void = { _ in }
    ) async -> AssetCacheBuildProgress {
        let clock = ContinuousClock()
        let start = clock.now
        var initial = AssetCacheBuildProgress()
        initial.totalFiles = items.count
        initial.totalBytes = items
            .reduce(0) { $0 + (files.provenance(forPath: $1.path)?.size ?? 0) }
        let state = Mutex(initial)
        let next = Atomic<Int>(0)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< max(1, width) {
                group.addTask { [self] in
                    while !control.isCancelled {
                        let index = next.add(1, ordering: .relaxed).oldValue
                        guard index < items.count else { return }
                        let outcome = convert(items[index])
                        let snapshot = state.withLock { progress in
                            progress.apply(outcome, item: items[index])
                            progress.elapsedSeconds = (clock.now - start).seconds
                            return progress
                        }
                        report(snapshot)
                    }
                }
            }
        }
        store.enforceLimit()
        return state.withLock { progress in
            progress.isCancelled = control.isCancelled && !progress.isFinished
            progress.elapsedSeconds = (clock.now - start).seconds
            return progress
        }
    }

    func request(
        for item: AssetCacheBuildItem,
        provenance: GameFileProvenance
    ) -> AssetCacheRequest {
        let source = AssetSourceStamp(
            origin: provenance.origin, path: item.path, size: provenance.size,
            modified: provenance.modified
        )
        return AssetCacheRequest(
            kind: item.converter.kind, source: source, converterVersion: item.converter.version,
            output: item.converter.kind == .texture ? textureOutput.variant(forPath: item.path) : 0
        )
    }

    enum Outcome {
        case converted(bytes: UInt64)
        case current(bytes: UInt64)
        case notStored(bytes: UInt64)
        case failed(String)
    }

    func convert(_ item: AssetCacheBuildItem) -> Outcome {
        guard let provenance = files.provenance(forPath: item.path) else {
            return .failed("no file provides this path")
        }
        let request = request(for: item, provenance: provenance)
        if store.isCurrent(request) {
            return .current(bytes: provenance.size)
        }
        do {
            let bytes = try files.contents(forPath: item.path)
            guard
                let payload = try item.converter.convert(
                    path: item.path,
                    bytes: bytes,
                    output: textureOutput
                )
            else {
                // An empty entry records that the original loads, so a check counts it as current.
                try store.store(Data(), for: request, enforcingLimit: false)
                return .notStored(bytes: provenance.size)
            }
            try store.store(payload, for: request, enforcingLimit: false)
            return .converted(bytes: provenance.size)
        } catch {
            return .failed(String(describing: error))
        }
    }
}

nonisolated extension AssetCacheBuildProgress {
    mutating func apply(_ outcome: AssetCacheBuilder.Outcome, item: AssetCacheBuildItem) {
        doneFiles += 1
        switch outcome {
        case let .converted(bytes):
            converted += 1
            doneBytes += bytes
        case let .current(bytes):
            alreadyCurrent += 1
            doneBytes += bytes
        case let .notStored(bytes):
            notStored += 1
            doneBytes += bytes
        case let .failed(reason):
            failures.append(AssetCacheBuildFailure(
                path: item.path,
                kind: item.converter.kind,
                reason: reason
            ))
        }
    }
}

nonisolated extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

nonisolated extension AssetCacheBuildProgress {
    /// One line for a log or a status label.
    public var summaryLine: String {
        let left = estimatedSecondsLeft.map { " about \(Int($0.rounded())) s left," } ?? ""
        let files = "\(doneFiles)/\(totalFiles) files, \(doneBytes >> 20)/\(totalBytes >> 20) MiB,"
        return files + "\(left) \(converted) converted, \(alreadyCurrent) current, "
            + "\(notStored) not stored, \(failures.count) failed"
    }
}

/// Lets one progress report through per interval, from any worker thread.
nonisolated public final class AssetCacheProgressThrottle: Sendable {
    private let interval: Duration
    private let last = Mutex<ContinuousClock.Instant?>(nil)

    public init(interval: Duration) {
        self.interval = interval
    }

    /// True for the first call and then once per interval; a finished build always passes.
    public func shouldReport(_ progress: AssetCacheBuildProgress) -> Bool {
        let now = ContinuousClock.now
        return last.withLock { last in
            guard progress.isFinished || last.map({ now - $0 >= interval }) ?? true
            else { return false }
            last = now
            return true
        }
    }
}
