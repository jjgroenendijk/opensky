// PIDN, MRKS, and FOGM chunks: the player's identity, map marker state, and the
// local map fog. Layout: docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface
import OpenSkyWorldState

nonisolated extension OpenSkySaveFormat.ChunkTag {
    /// The player's race, sex, name, and face.
    public static let playerIdentity = "PIDN"
    /// Map markers whose visible, discovered, or travel flags changed.
    public static let mapMarkers = "MRKS"
    /// The local map's explored squares per cell.
    public static let localMapFog = "FOGM"
}

nonisolated extension OpenSkySaveFormat {
    /// Key, cell tag, race, sex, and an empty name: the smallest PIDN entry.
    static let minimumIdentityEntrySize = 12
    static let minimumMarkerEntrySize = 9
    static let minimumFogEntrySize = 9
    /// Cell tag plus an interior FormID and the mask, the smallest fog row.
    static let minimumFogRowSize = 9
}

nonisolated extension OpenSkySaveEncoder {
    public static func writeIdentityAndMap(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let identityTag = OpenSkySaveFormat.ChunkTag.playerIdentity
        writeStory(PlayerIdentityState.self, tag: identityTag, entries, &writer) { state, payload in
            payload.writeUInt32(state.race.rawValue)
            payload.writeUInt8(state.isFemale ? 1 : 0)
            writeString(state.name, into: &payload)
            writeFace(state.face, into: &payload)
        }
        let markerTag = OpenSkySaveFormat.ChunkTag.mapMarkers
        writeStory(MapMarkerState.self, tag: markerTag, entries, &writer) { state, payload in
            let flags = (state.isVisible ? 1 : 0) | (state.isDiscovered ? 2 : 0)
                | (state.canTravelTo ? 4 : 0)
            payload.writeUInt8(UInt8(flags))
        }
        let fogTag = OpenSkySaveFormat.ChunkTag.localMapFog
        writeStory(LocalMapFogState.self, tag: fogTag, entries, &writer) { state, payload in
            let rows = state.explored.sorted {
                $0.key.saveOrder.lexicographicallyPrecedes($1.key.saveOrder)
            }
            payload.writeUInt32(UInt32(clamping: rows.count))
            for (cell, mask) in rows {
                writeCell(cell, into: &payload)
                payload.writeUInt64(mask)
            }
        }
    }

    private static func writeFace(_ face: PlayerFace, into writer: inout BinaryWriter) {
        writer.writeUInt32(UInt32(clamping: face.morphs.count))
        face.morphs.forEach { writer.writeFloat32($0) }
        writer.writeUInt32(UInt32(clamping: face.parts.count))
        face.parts.forEach { writer.writeUInt32(UInt32(bitPattern: $0)) }
        writer.writeUInt32(UInt32(clamping: face.headParts.count))
        face.headParts.forEach { writer.writeUInt32($0.rawValue) }
        writer.writeUInt32(face.hairColor?.rawValue ?? 0)
        writer.writeUInt32(UInt32(clamping: face.tints.count))
        for tint in face.tints {
            writer.writeUInt16(tint.maskIndex)
            for channel in [tint.color.x, tint.color.y, tint.color.z, tint.color.w] {
                writer.writeUInt8(channel)
            }
            writer.writeFloat32(tint.strength)
        }
        writer.writeFloat32(face.weight)
        writer.writeFloat32(face.height)
    }
}

nonisolated extension CellSceneLocation {
    /// Exteriors before interiors, then by coordinate or FormID.
    var saveOrder: [Int64] {
        switch self {
        case let .exterior(cell): [0, Int64(cell.x), Int64(cell.y)]
        case let .interior(formID): [1, Int64(formID.rawValue)]
        }
    }
}

nonisolated extension OpenSkySaveStoryDecoder {
    public static func decodeIdentities(_ payload: Data) throws
        -> [SaveStoryEntry<PlayerIdentityState>]
    {
        let tag = OpenSkySaveFormat.ChunkTag.playerIdentity
        return try decode(
            payload, tag: tag, minimumSize: OpenSkySaveFormat.minimumIdentityEntrySize
        ) { reader in
            let race = try FormID(reader.uint32("PIDN race"))
            let female = try reader.bool("PIDN sex")
            let name = try reader.string("PIDN name")
            return try PlayerIdentityState(
                race: race, isFemale: female, name: name, face: decodeFace(&reader)
            )
        }
    }

    public static func decodeMarkers(_ payload: Data) throws -> [SaveStoryEntry<MapMarkerState>] {
        let tag = OpenSkySaveFormat.ChunkTag.mapMarkers
        return try decode(
            payload, tag: tag, minimumSize: OpenSkySaveFormat.minimumMarkerEntrySize
        ) { reader in
            let flags = try reader.uint8("MRKS flags")
            guard flags & ~0x07 == 0 else {
                throw OpenSkySaveError.invalidValue(context: "MRKS flags \(flags)")
            }
            return MapMarkerState(
                isVisible: flags & 1 != 0, isDiscovered: flags & 2 != 0, canTravelTo: flags & 4 != 0
            )
        }
    }

    public static func decodeFog(_ payload: Data) throws -> [SaveStoryEntry<LocalMapFogState>] {
        let tag = OpenSkySaveFormat.ChunkTag.localMapFog
        return try decode(
            payload, tag: tag, minimumSize: OpenSkySaveFormat.minimumFogEntrySize
        ) { reader in
            let count = try reader.uint32("FOGM cell count")
            try OpenSkySaveDecoder.validate(
                count: count, minimumElementSize: OpenSkySaveFormat.minimumFogRowSize,
                remaining: reader.bytesRemaining, chunk: tag
            )
            var explored: [CellSceneLocation: UInt64] = [:]
            for _ in 0 ..< count {
                guard let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader) else {
                    throw OpenSkySaveError.invalidValue(context: "FOGM row without a cell")
                }
                explored[cell] = try reader.uint64("FOGM mask")
            }
            return LocalMapFogState(explored: explored)
        }
    }

    private static func decodeFace(_ reader: inout SaveReader) throws -> PlayerFace {
        var face = PlayerFace()
        face.morphs = try list(&reader, "PIDN morphs", size: 4) { try $0.float32("PIDN morph") }
        face.parts = try list(&reader, "PIDN parts", size: 4) {
            try Int32(bitPattern: $0.uint32("PIDN part"))
        }
        face.headParts = try list(&reader, "PIDN head parts", size: 4) {
            try FormID($0.uint32("PIDN head part"))
        }
        let hair = try reader.uint32("PIDN hair color")
        face.hairColor = hair == 0 ? nil : FormID(hair)
        face.tints = try list(&reader, "PIDN tints", size: 10) { reader in
            let mask = try reader.uint16("PIDN tint mask")
            let color = try SIMD4(
                reader.uint8("PIDN tint r"), reader.uint8("PIDN tint g"),
                reader.uint8("PIDN tint b"), reader.uint8("PIDN tint a")
            )
            let strength = try reader.float32("PIDN tint strength")
            return PlayerTintLayer(maskIndex: mask, color: color, strength: strength)
        }
        face.weight = try reader.float32("PIDN weight")
        face.height = try reader.float32("PIDN height")
        guard face.weight.isFinite, face.height.isFinite, face.morphs.allSatisfy(\.isFinite) else {
            throw OpenSkySaveError.invalidValue(context: "PIDN holds a value that is not finite")
        }
        return face
    }

    private static func list<Element>(
        _ reader: inout SaveReader, _ context: String, size: Int,
        _ element: (inout SaveReader) throws -> Element
    ) throws -> [Element] {
        let count = try reader.uint32("\(context) count")
        try OpenSkySaveDecoder.validate(
            count: count, minimumElementSize: size, remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.playerIdentity
        )
        return try (0 ..< count).map { _ in try element(&reader) }
    }
}
