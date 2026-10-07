// The engine's read path: a loader asks for a converted asset by path, and gets
// it when the entry is current, or nil so it loads the original file. A stale or
// unreadable entry is never used: it is logged, deleted, and marked for rebuild.
// Safe to call from any loader thread.

import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData
import Synchronization

nonisolated public struct AssetCacheReadCounts: Equatable, Sendable {
    public var hits = 0
    public var misses = 0
    public var stale = 0
    public var unreadable = 0
    /// Entries that say the original file loads, because no converter stores it.
    public var original = 0

    public init() {}
}

/// One asset kind's converter, as the read path sees it.
nonisolated public struct AssetCacheDecoder<Value>: Sendable {
    public let kind: AssetCacheKind
    public let converterVersion: UInt32
    public let decode: @Sendable (Data) throws -> Value

    public init(
        kind: AssetCacheKind,
        converterVersion: UInt32,
        decode: @escaping @Sendable (Data) throws -> Value
    ) {
        self.kind = kind
        self.converterVersion = converterVersion
        self.decode = decode
    }
}

nonisolated public struct AssetCacheEntryRead<Value> {
    public let value: Value
    public let file: URL
    /// Bytes from the start of the entry file to the first payload byte.
    public let payloadOffset: Int
}

nonisolated public struct AssetCacheRebuildItem: Hashable, Sendable {
    public let kind: AssetCacheKind
    public let path: String
}

nonisolated public final class AssetCacheReader: Sendable {
    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "AssetCache"
    )

    public let store: AssetCacheStore
    private let files: any GameFileSource
    private struct State {
        var isEnabled: Bool
        var preset: AssetQualityPreset
        var kinds: Set<AssetCacheKind>
        var counts: [AssetCacheKind: AssetCacheReadCounts] = [:]
        var rebuild: Set<AssetCacheRebuildItem> = []
        var requested: Set<String> = []
    }

    private let state: Mutex<State>

    public init(
        store: AssetCacheStore,
        files: any GameFileSource,
        preset: AssetQualityPreset,
        isEnabled: Bool = true,
        kinds: Set<AssetCacheKind> = Set(AssetCacheKind.built)
    ) {
        self.store = store
        self.files = files
        state = Mutex(State(isEnabled: isEnabled, preset: preset, kinds: kinds))
    }

    /// Off means every load reads the original files, for comparison.
    public var isEnabled: Bool {
        get { state.withLock { $0.isEnabled } }
        set { state.withLock { $0.isEnabled = newValue } }
    }

    public var preset: AssetQualityPreset {
        get { state.withLock { $0.preset } }
        set { state.withLock { $0.preset = newValue } }
    }

    /// A kind left out reads the original files; its entries stay on disk.
    public var kinds: Set<AssetCacheKind> {
        get { state.withLock { $0.kinds } }
        set { state.withLock { $0.kinds = newValue } }
    }

    public func counts(for kind: AssetCacheKind) -> AssetCacheReadCounts {
        state.withLock { $0.counts[kind] ?? AssetCacheReadCounts() }
    }

    /// Every path a lookup asked for, so a benchmark can build the cache for just its own assets.
    public var requestedPaths: Set<String> {
        state.withLock { $0.requested }
    }

    /// The counts of every kind read so far.
    public var allCounts: [AssetCacheKind: AssetCacheReadCounts] {
        state.withLock { $0.counts }
    }

    /// Entries a lookup found stale or broken since the last call.
    public func takeRebuildItems() -> Set<AssetCacheRebuildItem> {
        state.withLock { state in
            defer { state.rebuild.removeAll() }
            return state.rebuild
        }
    }

    /// The source stamp the cache keys `path` by, or nil when no file provides it.
    public func stamp(forPath path: String) -> AssetSourceStamp? {
        guard
            let normalized = try? VirtualFileSystem.normalize(path),
            let provenance = files.provenance(forPath: normalized)
        else { return nil }
        return AssetSourceStamp(
            origin: provenance.origin, path: normalized, size: provenance.size,
            modified: provenance.modified
        )
    }

    /// The decoded entry for `path`, or nil when the caller must load the original.
    public func value<Value>(forPath path: String, decoder: AssetCacheDecoder<Value>) -> Value? {
        entry(forPath: path, decoder: decoder)?.value
    }

    /// The decoded entry and where its payload lies in the entry file, for a
    /// loader that reads the file itself, such as Metal fast resource loading.
    public func entry<Value>(
        forPath path: String, decoder: AssetCacheDecoder<Value>
    ) -> AssetCacheEntryRead<Value>? {
        resolve(path: path, decoder: decoder) { store.lookup($0) }
    }

    /// The layout block of the cached model for `path`, read without the rest of the
    /// entry, for a loader that reads the mesh bytes itself.
    public func modelLayout(forPath path: String) -> AssetCacheEntryRead<ReadyModelLayout>? {
        resolve(path: path, decoder: .modelLayout) { request in
            store.lookupHead(request) { ModelCacheCodec.layoutByteCount(head: $0) }
        }
    }

    private func resolve<Value>(
        path: String, decoder: AssetCacheDecoder<Value>,
        lookup: (AssetCacheRequest) -> AssetCacheLookup
    ) -> AssetCacheEntryRead<Value>? {
        let (enabled, preset) = state.withLock {
            ($0.isEnabled && $0.kinds.contains(decoder.kind), $0.preset)
        }
        guard enabled, let source = stamp(forPath: path) else { return nil }
        state.withLock { _ = $0.requested.insert(source.path) }
        let request = AssetCacheRequest(
            kind: decoder.kind, source: source, converterVersion: decoder.converterVersion,
            preset: preset
        )
        switch lookup(request) {
        case let .hit(hit) where hit.payload.isEmpty:
            count(decoder.kind) { $0.original += 1 }
        case let .hit(hit):
            do {
                let value = try decoder.decode(hit.payload)
                count(decoder.kind) { $0.hits += 1 }
                return AssetCacheEntryRead(
                    value: value, file: hit.url,
                    payloadOffset: hit.payloadRange.lowerBound - hit.file.startIndex
                )
            } catch {
                reject(request, reason: "payload does not decode: \(error)") { $0.unreadable += 1 }
            }
        case .miss:
            count(decoder.kind) { $0.misses += 1 }
        case let .stale(staleness):
            reject(request, reason: "stale: \(staleness)") { $0.stale += 1 }
        case let .unreadable(reason):
            reject(request, reason: "unreadable: \(reason)") { $0.unreadable += 1 }
        }
        return nil
    }

    private func reject(
        _ request: AssetCacheRequest, reason: String, tally: (inout AssetCacheReadCounts) -> Void
    ) {
        Self.logger
            .warning(
                "[WARNING] cache entry \(request.kind) \(request.source.path) not used, \(reason)"
            )
        store.remove(kind: request.kind, source: request.source)
        state.withLock { state in
            tally(&state.counts[request.kind, default: AssetCacheReadCounts()])
            state.rebuild.insert(AssetCacheRebuildItem(
                kind: request.kind,
                path: request.source.path
            ))
        }
    }

    private func count(_ kind: AssetCacheKind, _ tally: (inout AssetCacheReadCounts) -> Void) {
        state.withLock { tally(&$0.counts[kind, default: AssetCacheReadCounts()]) }
    }
}
