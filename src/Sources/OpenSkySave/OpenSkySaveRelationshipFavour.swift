// The RELF chunk: per relationship pair, the rank it held when it first reached
// Friend, which fixes the item allowance. A sibling of `RELS`, whose overrides have a
// fixed layout. A pair with no `RELS` row is dropped: `RELS` says which pairs exist.
// See docs/formats/opensky-save-actor-chunks.md.

public import Foundation
import OpenSkyFactionsInterface
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyWorldState

/// One actor's first-friend ranks, before they lay onto its `RELS` overrides.
nonisolated public struct SaveRelationshipFavourEntry: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let other: ReferenceKey
        public let firstFriendRank: Int8
    }

    public let key: ReferenceKey
    public let rows: [Row]
}

nonisolated extension OpenSkySaveEncoder {
    /// The `RELF` chunk, in the snapshot's `ReferenceKey` order.
    public static func writeRelationshipFavour(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap(favourRows(of:))
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.relationshipFavour, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for entry in saved {
                writeKey(entry.key, into: &payload)
                payload.writeUInt32(UInt32(clamping: entry.rows.count))
                for row in entry.rows {
                    writeKey(row.other, into: &payload)
                    payload.writeUInt8(UInt8(bitPattern: row.firstFriendRank))
                }
            }
        }
    }

    private static func favourRows(
        of entry: WorldStateSnapshotEntry
    ) -> SaveRelationshipFavourEntry? {
        guard let state = entry.delta.component(ActorRelationshipState.self) else { return nil }
        var rows: [SaveRelationshipFavourEntry.Row] = []
        for override in state.overrides {
            if let rank = override.firstFriendRank {
                rows.append(.init(other: override.other, firstFriendRank: rank))
            }
        }
        return rows.isEmpty ? nil : SaveRelationshipFavourEntry(key: entry.key, rows: rows)
    }
}

nonisolated extension OpenSkySaveRelationshipDecoder {
    public static func decodeRelationshipFavour(
        _ payload: Data
    ) throws -> [SaveRelationshipFavourEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("RELF entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumRelationshipFavourEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.relationshipFavour
        )
        var entries: [SaveRelationshipFavourEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let rowCount = try reader.uint32("RELF row count")
            try OpenSkySaveDecoder.validate(
                count: rowCount,
                minimumElementSize: OpenSkySaveFormat.minimumRelationshipFavourRowSize,
                remaining: reader.bytesRemaining,
                chunk: OpenSkySaveFormat.ChunkTag.relationshipFavour
            )
            var rows: [SaveRelationshipFavourEntry.Row] = []
            rows.reserveCapacity(Int(rowCount))
            for _ in 0 ..< rowCount {
                let other = try OpenSkySaveEntryDecoder.decodeKey(&reader)
                let rank = try Int8(bitPattern: reader.uint8("RELF row rank"))
                rows.append(.init(other: other, firstFriendRank: rank))
            }
            entries.append(SaveRelationshipFavourEntry(key: key, rows: rows))
        }
        return entries
    }

    /// The `RELS` entries with each pair's first-friend rank laid on.
    public static func layingFavour(
        _ favours: [SaveRelationshipFavourEntry],
        onto relationships: [SaveRelationshipEntry]
    ) -> [SaveRelationshipEntry] {
        guard !favours.isEmpty else { return relationships }
        var byKey: [ReferenceKey: [ReferenceKey: Int8]] = [:]
        for favour in favours {
            for row in favour.rows {
                byKey[favour.key, default: [:]][row.other] = row.firstFriendRank
            }
        }
        return relationships.map { saved in
            guard let ranks = byKey[saved.key] else { return saved }
            let overrides = saved.state.overrides.map { override in
                ActorRelationshipOverride(
                    other: override.other,
                    rank: override.rank,
                    firstFriendRank: ranks[override.other]
                )
            }
            return SaveRelationshipEntry(
                key: saved.key,
                cell: saved.cell,
                state: ActorRelationshipState(overrides: overrides)
            )
        }
    }
}

nonisolated extension OpenSkySaveDecoder {
    /// `RELS` with `RELF` laid on.
    static func relationships(of body: Body) -> [SaveRelationshipEntry] {
        OpenSkySaveRelationshipDecoder.layingFavour(
            body.relationshipFavour, onto: body.relationships
        )
    }

    static func applyRelationships(tag: String, payload: Data, to body: inout Body) throws {
        if tag == OpenSkySaveFormat.ChunkTag.relationshipFavour {
            body.relationshipFavour = try OpenSkySaveRelationshipDecoder
                .decodeRelationshipFavour(payload)
        } else {
            body.relationships = try OpenSkySaveRelationshipDecoder
                .decodeRelationshipRanks(payload)
        }
    }
}
