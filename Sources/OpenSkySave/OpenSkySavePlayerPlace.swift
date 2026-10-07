// PLOC chunk: where the player stood when the game was saved, so a load puts the
// player back there. Layout: docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData

nonisolated extension OpenSkySaveFormat.ChunkTag {
    /// The player's cell, feet position, and facing.
    public static let playerPlace = "PLOC"
}

/// The player's place at save time. Interior `feet` are local to its cell.
nonisolated public struct SavePlayerPlace: Equatable, Sendable {
    public let cell: CellSceneLocation
    public let feet: SIMD3<Float>
    /// Radians, the camera's yaw.
    public let yaw: Float

    public init(cell: CellSceneLocation, feet: SIMD3<Float>, yaw: Float) {
        self.cell = cell
        self.feet = feet
        self.yaw = yaw
    }
}

nonisolated extension OpenSkySaveEncoder {
    static func writePlayerPlace(_ place: SavePlayerPlace, into writer: inout BinaryWriter) {
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.playerPlace, into: &writer) { payload in
            writeCell(place.cell, into: &payload)
            for value in [place.feet.x, place.feet.y, place.feet.z, place.yaw] {
                payload.writeFloat32(value)
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
        return SavePlayerPlace(
            cell: cell, feet: SIMD3(values[0], values[1], values[2]), yaw: values[3]
        )
    }
}
