// PCPX chunk: the player's complexion, a face texture set the race menu picks.
// A sibling of PIDN, whose entries have no length, so appending a field there would
// break older readers. Layout: docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

nonisolated extension OpenSkySaveFormat.ChunkTag {
    /// The complexion texture set (`FTST`) per identity holder.
    public static let playerComplexion = "PCPX"
}

nonisolated extension OpenSkySaveFormat {
    /// A plugin key with an empty name (1 + 2 + 4) and the texture set FormID (4).
    static let minimumComplexionEntrySize = 11
}

nonisolated extension OpenSkySaveEncoder {
    static func writeComplexions(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> (ReferenceKey, FormID)? in
            entry.delta.component(PlayerIdentityState.self)?.face.faceTexture
                .map { (entry.key, $0) }
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.playerComplexion, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (key, texture) in saved {
                writeKey(key, into: &payload)
                payload.writeUInt32(texture.rawValue)
            }
        }
    }
}

nonisolated extension OpenSkySaveDecoder {
    /// The identity, complexion, and map chunks; false for any other tag.
    static func applyIdentityAndMap(
        tag: String,
        payload: Data,
        to body: inout Body
    ) throws -> Bool {
        switch tag {
        case OpenSkySaveFormat.ChunkTag.playerIdentity:
            body.identities = try OpenSkySaveStoryDecoder.decodeIdentities(payload)
        case OpenSkySaveFormat.ChunkTag.playerComplexion:
            body.complexions = try OpenSkySaveStoryDecoder.decodeComplexions(payload)
        case OpenSkySaveFormat.ChunkTag.mapMarkers:
            body.markers = try OpenSkySaveStoryDecoder.decodeMarkers(payload)
        case OpenSkySaveFormat.ChunkTag.localMapFog:
            body.fog = try OpenSkySaveStoryDecoder.decodeFog(payload)
        default:
            return false
        }
        return true
    }
}

nonisolated extension OpenSkySaveStoryDecoder {
    public static func decodeComplexions(_ payload: Data) throws -> [ReferenceKey: FormID] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("PCPX entry count")
        try OpenSkySaveDecoder.validate(
            count: count, minimumElementSize: OpenSkySaveFormat.minimumComplexionEntrySize,
            remaining: reader.bytesRemaining, chunk: OpenSkySaveFormat.ChunkTag.playerComplexion
        )
        var complexions: [ReferenceKey: FormID] = [:]
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            complexions[key] = try FormID(reader.uint32("PCPX texture set"))
        }
        return complexions
    }

    /// Lays each complexion onto its `PIDN` identity; one without an identity is dropped.
    public static func mergeComplexions(
        _ complexions: [ReferenceKey: FormID],
        into identities: [SaveStoryEntry<PlayerIdentityState>]
    ) -> [SaveStoryEntry<PlayerIdentityState>] {
        guard !complexions.isEmpty else { return identities }
        return identities.map { entry in
            guard let texture = complexions[entry.key] else { return entry }
            var state = entry.state
            state.face.faceTexture = texture
            return SaveStoryEntry(key: entry.key, cell: entry.cell, state: state)
        }
    }
}
