// STOF chunk: what the player stole from each owning faction, so a friend's favour can
// clear the stolen flag after a load too. Rows ascend by owner, then item.
// Layout: docs/formats/opensky-save-actor-chunks.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// Per row: the owning faction's key, the item FormID, and the count.
    static func writeStolenOrigins(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        writeStory(
            (StolenOriginsState.self, OpenSkySaveFormat.ChunkTag.stolenOrigins), entries, &writer
        ) { state, payload in
            payload.writeUInt32(UInt32(clamping: state.origins.count))
            for origin in state.origins {
                payload.writeKey(origin.owner)
                payload.writeUInt32(origin.item.rawValue)
                payload.writeUInt32(UInt32(bitPattern: origin.count))
            }
        }
    }
}

nonisolated extension OpenSkySaveStoryDecoder {
    static func decodeStolenOrigins(
        _ payload: Data
    ) throws -> [SaveStoryEntry<StolenOriginsState>] {
        let tag = OpenSkySaveFormat.ChunkTag.stolenOrigins
        return try decode(
            payload, tag: tag, minimumSize: OpenSkySaveFormat.minimumStolenOriginsEntrySize
        ) { reader in
            let count = try reader.uint32("STOF row count")
            try SaveCountCheck.validate(
                count: count, minimumElementSize: OpenSkySaveFormat.minimumStolenOriginRowSize,
                remaining: reader.bytesRemaining, chunk: tag
            )
            var origins: [StolenOrigin] = []
            for _ in 0 ..< count {
                let owner = try OpenSkySaveEntryDecoder.decodeKey(&reader)
                let item = try FormID(reader.uint32("STOF item"))
                let amount = try Int32(bitPattern: reader.uint32("STOF count"))
                origins.append(StolenOrigin(owner: owner, item: item, count: amount))
            }
            return StolenOriginsState(origins: origins)
        }
    }
}
