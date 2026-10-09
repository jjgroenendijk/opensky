// How much of a planned build the cache already holds, per kind. Reads only the
// entry headers, so it is quick enough to run when the cache page opens.

import Foundation
import OpenSkyGameData

nonisolated public struct AssetCacheKindCheck: Equatable, Sendable {
    public var current = 0
    public var stale = 0
    public var missing = 0
    /// Source bytes of the stale and missing files: what a conversion still reads.
    public var pendingSourceBytes: UInt64 = 0

    public init(
        current: Int = 0,
        stale: Int = 0,
        missing: Int = 0,
        pendingSourceBytes: UInt64 = 0
    ) {
        self.current = current
        self.stale = stale
        self.missing = missing
        self.pendingSourceBytes = pendingSourceBytes
    }

    public var total: Int {
        current + stale + missing
    }

    public var pending: Int {
        stale + missing
    }
}

nonisolated public struct AssetCacheCheck: Equatable, Sendable {
    public var kinds: [AssetCacheKind: AssetCacheKindCheck] = [:]

    public init() {}

    public var total: AssetCacheKindCheck {
        kinds.values.reduce(into: AssetCacheKindCheck()) { sum, kind in
            sum.current += kind.current
            sum.stale += kind.stale
            sum.missing += kind.missing
            sum.pendingSourceBytes += kind.pendingSourceBytes
        }
    }

    public enum Summary: Equatable, Sendable {
        case notBuilt
        case partlyBuilt
        case stale
        case current
    }

    /// Stale wins over partly built: a changed install or texture output needs a rebuild.
    public var summary: Summary {
        let total = total
        if total.stale > 0 {
            return .stale
        }
        if total.missing == 0 {
            return .current
        }
        return total.current == 0 ? .notBuilt : .partlyBuilt
    }
}

nonisolated extension AssetCacheBuilder {
    /// Counts the entries of `items` by state.
    @concurrent
    public func check(_ items: [AssetCacheBuildItem]) async -> AssetCacheCheck {
        var check = AssetCacheCheck()
        for item in items {
            guard let provenance = files.provenance(forPath: item.path) else { continue }
            let state = store.entryState(request(for: item, provenance: provenance))
            var kind = check.kinds[item.converter.kind] ?? AssetCacheKindCheck()
            switch state {
            case .current: kind.current += 1
            case .stale: kind.stale += 1
            case .missing: kind.missing += 1
            }
            if state != .current {
                kind.pendingSourceBytes += provenance.size
            }
            check.kinds[item.converter.kind] = kind
        }
        return check
    }
}
