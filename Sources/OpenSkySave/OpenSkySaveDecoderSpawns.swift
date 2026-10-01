// SPWN chunk: objects the game placed, merged into the `RDLT` deltas by
// `ReferenceKey`. A spawn usually has no `RDLT` entry of its own.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState
import simd

/// One saved spawned object, before it is merged back into its delta.
nonisolated public struct SaveSpawnEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let spawn: ReferenceSpawnState
}

nonisolated public enum OpenSkySaveSpawnDecoder: Sendable {
    public static func decodeSpawns(_ payload: Data) throws -> [SaveSpawnEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("SPWN entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumSpawnEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.spawnedReferences
        )
        var entries: [SaveSpawnEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    // MARK: - Private

    /// An entry whose cell tag says "absent" is rejected rather than defaulted:
    /// `ReferenceSpawnState` requires a cell because an object with none is not
    /// in the world, and inventing one would put a dropped item somewhere the
    /// player never stood.
    private static func decodeEntry(_ reader: inout SaveReader) throws -> SaveSpawnEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let base = try FormID(reader.uint32("SPWN base form ID"))
        guard let location = try OpenSkySaveEntryDecoder.decodeCell(&reader) else {
            throw OpenSkySaveError.invalidValue(
                context: "SPWN entry for \(key) names no cell"
            )
        }
        let position = try vector(&reader, "SPWN position")
        let rotation = try vector(&reader, "SPWN rotation")
        let scale = try reader.float32("SPWN scale")
        let count = try Int32(bitPattern: reader.uint32("SPWN count"))
        return SaveSpawnEntry(
            key: key,
            spawn: ReferenceSpawnState(
                base: base,
                location: location,
                placement: PlacedReference.Placement(position: position, rotation: rotation),
                scale: scale,
                count: count
            )
        )
    }

    private static func vector(
        _ reader: inout SaveReader,
        _ context: String
    ) throws -> SIMD3<Float> {
        let x = try reader.float32("\(context) x")
        let y = try reader.float32("\(context) y")
        let z = try reader.float32("\(context) z")
        return SIMD3(x, y, z)
    }
}

nonisolated extension SaveSpawnEntry: SaveDeltaComponentEntry {
    public var deltaCell: CellSceneLocation? {
        spawn.location
    }

    public var deltaComponent: WorldStateComponentValue? {
        spawn.erased
    }
}
