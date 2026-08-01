// SPWN chunk writing for the OpenSky native save container (issue #177).
//
// A satellite of `OpenSkySaveEncoder` for the same reason the `INVN` writer is
// one: the encoder body is already at the type-length limit, and the three
// shared writers this needs — `writeChunk`, `writeKey`, `writeCell` — are
// internal on the parent precisely so a chunk can live in its own file.

import Foundation

nonisolated extension OpenSkySaveEncoder {
    /// One spawned object paired with the snapshot entry it came from.
    private struct SpawnedObject {
        let key: ReferenceKey
        let spawn: ReferenceSpawnState
    }

    /// The `SPWN` chunk: every snapshot entry carrying a spawn component, in
    /// the snapshot's `ReferenceKey` order.
    ///
    /// The entry repeats its key rather than referring back to an `RDLT` entry,
    /// because an object whose only delta is its spawn has no `RDLT` entry at
    /// all — the same reasoning `INVN` follows. The cell written here is the
    /// component's own `location`, not the delta's attribution cell: the former
    /// says where the object is and the latter says where it was last touched,
    /// and only the first belongs in the world.
    static func writeSpawnedReferences(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let spawned = entries.compactMap { entry -> SpawnedObject? in
            guard let spawn = entry.delta.component(ReferenceSpawnState.self) else { return nil }
            return SpawnedObject(key: entry.key, spawn: spawn)
        }
        guard !spawned.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.spawnedReferences, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: spawned.count))
            for each in spawned {
                writeKey(each.key, into: &payload)
                payload.writeUInt32(each.spawn.base.rawValue)
                writeCell(each.spawn.location, into: &payload)
                writePlacement(each.spawn, into: &payload)
            }
        }
    }

    /// Position, rotation, scale and count. Floats go out as their IEEE bit
    /// pattern through `writeFloat32`, so the bytes are an exact function of
    /// the state rather than of a decimal conversion.
    private static func writePlacement(
        _ spawn: ReferenceSpawnState,
        into writer: inout BinaryWriter
    ) {
        for vector in [spawn.placement.position, spawn.placement.rotation] {
            writer.writeFloat32(vector.x)
            writer.writeFloat32(vector.y)
            writer.writeFloat32(vector.z)
        }
        writer.writeFloat32(spawn.scale)
        writer.writeUInt32(UInt32(bitPattern: spawn.count))
    }
}
