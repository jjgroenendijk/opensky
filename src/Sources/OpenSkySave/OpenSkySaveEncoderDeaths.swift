// DETH chunk writing. Each entry carries its cell. The resting transforms are optional: a
// corpse or a cut head still falling has none, and a mid-air pose would float on reload.

import Foundation
public import OpenSkyActorsInterface
import OpenSkyFormatsCore
public import OpenSkyWorldState

nonisolated enum OpenSkySaveDeathsWriter {
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
        writer.writeChunk(tag: OpenSkySaveFormat.ChunkTag.deaths) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                payload.writeKey(each.entry.key)
                payload.writeCell(each.entry.delta.cell)
                payload.writeUInt8(each.state.isDead ? 1 : 0)
                payload.writeUInt8(each.state.wasLooted ? 1 : 0)
                writeRestingTransform(each.state.restingTransform, into: &payload)
                payload.writeUInt8(Self.cutByte(each.state))
                if let node = each.state.severedNode {
                    payload.writeString(node)
                }
                writeRestingTransform(each.state.severedHeadRest, into: &payload)
            }
        }
    }

    /// A presence byte, then position, rotation and scale when there is one.
    /// The same field order and float encoding `RDLT` gives a transform
    /// override, so the two read the same way in a hex dump.
    /// 0 for a whole body, 1 for a cut node, 2 for a node blown off.
    private static func cutByte(_ state: ActorDeathState) -> UInt8 {
        guard state.severedNode != nil else { return 0 }
        return state.partExploded ? 2 : 1
    }

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
