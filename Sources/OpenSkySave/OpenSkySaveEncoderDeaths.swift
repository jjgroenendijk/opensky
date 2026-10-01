// DETH chunk writing. Each entry carries its cell. The resting transform is optional: a
// corpse still falling has none, and a mid-air pose would float on reload.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsCore
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// One actor's death paired with the snapshot entry it came from.
    private struct SavedDeath {
        let entry: WorldStateSnapshotEntry
        let state: ActorDeathState
    }

    /// The `DETH` chunk: every snapshot entry carrying a death component, in
    /// the snapshot's `ReferenceKey` order. A session in which nothing died
    /// writes no chunk.
    public static func writeDeaths(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> SavedDeath? in
            guard let state = entry.delta.component(ActorDeathState.self) else { return nil }
            return SavedDeath(entry: entry, state: state)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.deaths, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.entry.key, into: &payload)
                writeCell(each.entry.delta.cell, into: &payload)
                payload.writeUInt8(each.state.isDead ? 1 : 0)
                payload.writeUInt8(each.state.wasLooted ? 1 : 0)
                writeRestingTransform(each.state.restingTransform, into: &payload)
            }
        }
    }

    /// A presence byte, then position, rotation and scale when there is one.
    /// The same field order and float encoding `RDLT` gives a transform
    /// override, so the two read the same way in a hex dump.
    private static func writeRestingTransform(
        _ transform: ReferenceTransformOverride?,
        into writer: inout BinaryWriter
    ) {
        guard let transform else {
            writer.writeUInt8(0)
            return
        }
        writer.writeUInt8(1)
        for component in [transform.position, transform.rotation] {
            writer.writeFloat32(component.x)
            writer.writeFloat32(component.y)
            writer.writeFloat32(component.z)
        }
        writer.writeFloat32(transform.scale)
    }
}
