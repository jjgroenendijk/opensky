// DETH chunk writing for the OpenSky native save container (issue #197).
//
// A satellite of `OpenSkySaveEncoder` for the same reason the INVN, QSTS and
// AVAL writers are: the encoder is at its type-length limit. The three shared
// writers it uses — `writeChunk`, `writeKey`, `writeCell` — are internal on the
// parent for exactly this reason.
//
// The cell travels with each entry, as it does for an actor's values: an actor
// is a placed reference and its cell is what the store's per-cell dirty counts
// are keyed by.
//
// The resting transform is optional in the bytes as well as in the type. A
// corpse still falling when the save was written has none, and writing a
// mid-flight pose would put the body back in the air on reload.

import Foundation

nonisolated extension OpenSkySaveEncoder {
    /// One actor's death paired with the snapshot entry it came from.
    private struct SavedDeath {
        let entry: WorldStateSnapshotEntry
        let state: ActorDeathState
    }

    /// The `DETH` chunk: every snapshot entry carrying a death component, in
    /// the snapshot's `ReferenceKey` order. A session in which nothing died
    /// writes no chunk.
    static func writeDeaths(
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
