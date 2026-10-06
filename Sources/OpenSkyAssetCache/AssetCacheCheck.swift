// How much of a planned build the cache already holds, per kind. Reads only the
// entry headers, so it is quick enough to run when the cache page opens.

import Foundation
import OpenSkyGameData

nonisolated public struct AssetCacheKindCheck: Equatable, Sendable {
    public var current = 0
    public var stale = 0
    public var missing = 0

    public init(current: Int = 0, stale: Int = 0, missing: Int = 0) {
        self.current = current
        self.stale = stale
        self.missing = missing
    }

    public var total: Int {
        current + stale + missing
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
        }
    }

    public enum Summary: Equatable, Sendable {
        case notBuilt
        case partlyBuilt
        case stale
        case current
    }

    /// Stale wins over partly built: a changed install or preset needs a rebuild.
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
            switch store.entryState(request(for: item, provenance: provenance)) {
            case .current: check.kinds[item.converter.kind, default: AssetCacheKindCheck()]
                .current += 1
            case .stale: check.kinds[item.converter.kind, default: AssetCacheKindCheck()].stale += 1
            case .missing: check.kinds[item.converter.kind, default: AssetCacheKindCheck()]
                .missing += 1
            }
        }
        return check
    }
}
