// Which location an exterior cell belongs to, from the `LCEC` and `ACEC` cell lists of
// every LCTN, less its `RCEC` list. See docs/formats/locations.md#cell-link.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct LocationCellMap: Sendable {
    private struct Key: Hashable {
        let worldspace: ResolvedFormID
        let x: Int32
        let y: Int32
    }

    private var owners: [Key: ResolvedFormID] = [:]

    public static let empty = LocationCellMap()

    private init() {}

    /// A cell two locations list goes to the one deeper in the parent chain, so a
    /// town wins over its hold. A tie keeps the first in FormID order, so the result is stable.
    public init(store: LocationStore) {
        var depths: [Key: Int] = [:]
        let sorted = store.locations.sorted { $0.key.description < $1.key.description }
        for (id, resolved) in sorted {
            let depth = store.parentChain(of: id).count
            for key in Self.cells(of: resolved, store: store) {
                if let known = depths[key], known >= depth {
                    continue
                }
                depths[key] = depth
                owners[key] = id
            }
        }
    }

    public func location(worldspace: ResolvedFormID, x: Int32, y: Int32) -> ResolvedFormID? {
        owners[Key(worldspace: worldspace, x: x, y: y)]
    }

    private static func cells(of resolved: ResolvedLocation, store: LocationStore) -> Set<Key> {
        let location = resolved.location
        let listed = keys(location.worldspaceCells + location.addedWorldspaceCells, resolved, store)
        return listed.subtracting(keys(location.removedWorldspaceCells, resolved, store))
    }

    private static func keys(
        _ lists: [Location.WorldspaceCells],
        _ resolved: ResolvedLocation,
        _ store: LocationStore
    ) -> Set<Key> {
        var keys: Set<Key> = []
        for list in lists {
            guard
                let worldspace = store.resolvedID(
                    list.worldspace, fromPlugin: resolved.sourcePlugin
                )
            else { continue }
            for cell in list.cells {
                keys.insert(Key(worldspace: worldspace, x: Int32(cell.x), y: Int32(cell.y)))
            }
        }
        return keys
    }
}
