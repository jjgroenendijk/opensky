import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// A decoded side-chunk entry that stores one component on a reference's `RDLT` delta.
nonisolated public protocol SaveDeltaComponentEntry: Sendable {
    var key: ReferenceKey { get }
    /// The cell of a delta that the merge has to create.
    var deltaCell: CellSceneLocation? { get }
    /// The component to store, or nil when the entry changes nothing.
    var deltaComponent: WorldStateComponentValue? { get }
}

nonisolated enum OpenSkySaveDeltaMerge {
    /// Lays each component over the matching `RDLT` delta, adds a delta for a
    /// key that had none, and re-sorts the result into `ReferenceKey` order.
    static func merge(
        _ values: [some SaveDeltaComponentEntry],
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        let written = values.filter { $0.deltaComponent != nil }
        guard !written.isEmpty else { return entries }
        var deltasByKey = index(entries)
        for entry in written {
            guard let component = entry.deltaComponent else { continue }
            var delta = deltasByKey[entry.key] ?? ReferenceStateDelta(cell: entry.deltaCell)
            delta.set(component)
            deltasByKey[entry.key] = delta
        }
        return sorted(deltasByKey)
    }

    static func index(
        _ entries: [WorldStateSnapshotEntry]
    ) -> [ReferenceKey: ReferenceStateDelta] {
        var deltasByKey: [ReferenceKey: ReferenceStateDelta] = [:]
        deltasByKey.reserveCapacity(entries.count)
        for entry in entries {
            deltasByKey[entry.key] = entry.delta
        }
        return deltasByKey
    }

    static func sorted(
        _ deltasByKey: [ReferenceKey: ReferenceStateDelta]
    ) -> [WorldStateSnapshotEntry] {
        deltasByKey.keys.sorted().compactMap { key in
            deltasByKey[key].map { WorldStateSnapshotEntry(key: key, delta: $0) }
        }
    }
}
