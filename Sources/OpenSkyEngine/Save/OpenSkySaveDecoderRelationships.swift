// RELS chunk decoding for the OpenSky native save container (issue #508).
//
// Decoded on its own and merged into the `RDLT` entries afterwards, exactly
// like `FCTN`, `PRKS` and `SPLB`: an actor whose only delta is a scripted
// relationship rank has no `RDLT` entry, so merging by `ReferenceKey` is what
// lets the encoder omit one.
//
// Bounds, as everywhere else in this decoder: a declared count is checked
// against the bytes actually left before an array is reserved, so a corrupt
// length is a thrown error rather than a multi-gigabyte allocation.
//
// Nothing here rejects an override on content. A repeated actor collapses in
// `ActorRelationshipState.init`, and a rank outside the Creation Kit's -4...4 is
// kept, because the wiki names that range as "acceptable" without saying what a
// value outside it means and clamping would invent a rank the script did not
// set.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One actor's saved relationship overrides, before they are merged back into
/// the delta.
nonisolated public struct SaveRelationshipEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation?
    public let state: ActorRelationshipState
}

nonisolated public enum OpenSkySaveRelationshipDecoder: Sendable {
    public static func decodeRelationshipRanks(_ payload: Data) throws -> [SaveRelationshipEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("RELS entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumRelationshipEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.relationships
        )
        var entries: [SaveRelationshipEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    /// Lays each saved override list over the matching `RDLT` delta, adding an
    /// entry for an actor that had no other component, and re-sorts the result
    /// into `ReferenceKey` total order.
    public static func merge(
        _ values: [SaveRelationshipEntry],
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        guard !values.isEmpty else { return entries }
        var deltasByKey: [ReferenceKey: ReferenceStateDelta] = [:]
        deltasByKey.reserveCapacity(entries.count + values.count)
        for entry in entries {
            deltasByKey[entry.key] = entry.delta
        }
        for entry in values where !entry.state.isEmpty {
            var delta = deltasByKey[entry.key] ?? ReferenceStateDelta(cell: entry.cell)
            delta.set(entry.state.erased)
            deltasByKey[entry.key] = delta
        }
        return deltasByKey.keys.sorted().compactMap { key in
            guard let delta = deltasByKey[key] else { return nil }
            return WorldStateSnapshotEntry(key: key, delta: delta)
        }
    }

    // MARK: - Private

    private static func decodeEntry(
        _ reader: inout SaveReader
    ) throws -> SaveRelationshipEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let count = try reader.uint32("RELS override count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumRelationshipOverrideSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.relationships
        )
        var overrides: [ActorRelationshipOverride] = []
        overrides.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let other = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let rank = try Int8(bitPattern: reader.uint8("RELS override rank"))
            overrides.append(ActorRelationshipOverride(other: other, rank: rank))
        }
        return SaveRelationshipEntry(
            key: key,
            cell: cell,
            state: ActorRelationshipState(overrides: overrides)
        )
    }
}
