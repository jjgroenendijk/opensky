// What the player stole from each owning faction. A friend's favour later clears the
// stolen flag on these: UESP "Skyrim:Crime" says when a friend lets you take things
// from their home, "If you had previously stolen any of these items, they will also
// have their stolen status removed". Keyed by the thief. See docs/engine/crime.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyWorldState

/// How many of one item were stolen from one owning faction.
nonisolated public struct StolenOrigin: Equatable, Sendable {
    public let owner: ReferenceKey
    public let item: FormID
    public let count: Int32

    public init(owner: ReferenceKey, item: FormID, count: Int32) {
        self.owner = owner
        self.item = item
        self.count = count
    }
}

/// Every stolen item one actor still holds a record of, sorted by owner, then item.
nonisolated public struct StolenOriginsState: WorldStateComponent, Sendable {
    public private(set) var origins: [StolenOrigin]

    public static var componentKind: WorldStateComponentKind {
        .stolenOrigins
    }

    /// Merges rows for the same owner and item, and drops rows of no items.
    public init(origins: [StolenOrigin] = []) {
        var counts: [ReferenceKey: [UInt32: Int64]] = [:]
        for origin in origins {
            counts[origin.owner, default: [:]][origin.item.rawValue, default: 0] +=
                Int64(origin.count)
        }
        self.origins = counts.keys.sorted().flatMap { owner in
            (counts[owner] ?? [:]).sorted { $0.key < $1.key }.compactMap { item, count in
                count > 0
                    ? StolenOrigin(owner: owner, item: FormID(item), count: Int32(clamping: count))
                    : nil
            }
        }
    }

    public var isEmpty: Bool {
        origins.isEmpty
    }

    /// This record with `count` more of `item` stolen from `owner`.
    public func adding(_ item: FormID, count: Int32, from owner: ReferenceKey) -> Self {
        StolenOriginsState(origins: origins + [StolenOrigin(
            owner: owner,
            item: item,
            count: count
        )])
    }

    /// This record without the row of `item` stolen from `owner`.
    public func removing(_ item: FormID, from owner: ReferenceKey) -> Self {
        StolenOriginsState(origins: origins.filter { $0.owner != owner || $0.item != item })
    }
}

nonisolated extension WorldStateComponentKind {
    /// What one actor stole from each owning faction. Its own slot, because the crime
    /// ledger is keyed by the crime faction that charges, not the faction that owns.
    public static let stolenOrigins = Self(
        rawValue: "stolenOrigins", order: 46, affectsCellBuild: false
    )
}
