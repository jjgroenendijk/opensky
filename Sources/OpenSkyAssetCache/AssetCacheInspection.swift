// One asset's cache entries as the developer sidebar shows them: which kinds
// the path has, and whether each entry is current, stale, missing, or a marker
// that says the original file loads.

import Foundation

nonisolated public struct AssetCacheEntryInspection: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case current(payloadBytes: Int)
        /// An empty entry: no converter stores this file, so the original loads.
        case original
        case stale(String)
        case unreadable(String)
        case missing
    }

    public let kind: AssetCacheKind
    public let state: State
}

nonisolated extension AssetCacheKind {
    /// The kinds a source path can be cached as; a mesh also has a collision entry.
    public static func kinds(forPath path: String) -> [Self] {
        switch (path as NSString).pathExtension.lowercased() {
        case "dds": [.texture]
        case "nif": [.mesh, .collision]
        case "hkx": [.animation]
        case "wav", "xwm": [.audio]
        default: []
        }
    }

    public var converterVersion: UInt32 {
        switch self {
        case .texture: AssetConverterVersion.texture
        case .mesh: AssetConverterVersion.mesh
        case .collision: AssetConverterVersion.collision
        case .animation: AssetConverterVersion.animation
        case .audio: AssetConverterVersion.audio
        }
    }
}

nonisolated extension AssetCacheReader {
    /// Nil when no file provides `path`. Reads entries without touching their use date.
    public func inspect(path: String) -> [AssetCacheEntryInspection]? {
        guard let source = stamp(forPath: path) else { return nil }
        return AssetCacheKind.kinds(forPath: source.path).map { kind in
            let request = AssetCacheRequest(
                kind: kind, source: source, converterVersion: kind.converterVersion,
                output: kind == .texture ? textureOutput.variant(forPath: source.path) : 0
            )
            return AssetCacheEntryInspection(kind: kind, state: inspectionState(request))
        }
    }

    private func inspectionState(_ request: AssetCacheRequest) -> AssetCacheEntryInspection.State {
        switch store.lookup(request, touching: false) {
        case let .hit(hit) where hit.payload.isEmpty: .original
        case let .hit(hit): .current(payloadBytes: hit.payload.count)
        case .miss: .missing
        case let .stale(staleness): .stale(String(describing: staleness))
        case let .unreadable(reason): .unreadable(reason)
        }
    }
}
