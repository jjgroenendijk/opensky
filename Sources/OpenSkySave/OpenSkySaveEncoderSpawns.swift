// SPWN chunk writing, in its own file because the encoder body is at its length limit.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// One spawned object paired with the snapshot entry it came from.
    private struct SpawnedObject {
        let key: ReferenceKey
        let spawn: ReferenceSpawnState
    }

    /// The `SPWN` chunk: every spawn component, in key order, with its key repeated. The
    /// cell is the component's `location` (where it is), not the delta's attribution cell.
    public static func writeSpawnedReferences(
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
