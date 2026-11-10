// PLOC chunk: where the player stood when the game was saved, so a load puts the
// player back there. Layout: docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkySaveInterface

nonisolated extension OpenSkySaveFormat.ChunkTag {
    /// The player's cell, feet position, and facing.
    static let playerPlace = "PLOC"
}

nonisolated extension OpenSkySaveEncoder {
    static func writePlayerPlace(_ place: SavePlayerPlace, into writer: inout BinaryWriter) {
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.playerPlace, into: &writer) { payload in
            writeCell(place.cell, into: &payload)
            for value in [place.feet.x, place.feet.y, place.feet.z, place.yaw] {
                payload.writeFloat32(value)
            }
            if let worldspace = place.worldspace {
                writeString(worldspace, into: &payload)
            }
        }
    }
}

nonisolated extension OpenSkySaveDecoder {
    /// A missing cell or a value that is not finite is corruption, not a place.
    static func decodePlayerPlace(_ payload: Data) throws -> SavePlayerPlace {
        var reader = SaveReader(payload)
        guard let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader) else {
            throw OpenSkySaveError.invalidValue(context: "PLOC has no cell")
        }
        var values: [Float] = []
        for name in ["feet x", "feet y", "feet z", "yaw"] {
            let value = try reader.float32("PLOC \(name)")
            guard value.isFinite else {
                throw OpenSkySaveError.invalidValue(context: "PLOC \(name) is \(value)")
            }
            values.append(value)
        }
        let worldspace = reader.isAtEnd ? nil : try reader.string("PLOC worldspace")
        return SavePlayerPlace(
            cell: cell, feet: SIMD3(values[0], values[1], values[2]), yaw: values[3],
            worldspace: worldspace
        )
    }
}
