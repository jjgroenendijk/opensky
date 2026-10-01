// AVAL chunk writing. Each entry carries its cell, because an actor is a placed reference
// and the store's dirty counts are per cell.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// One actor's values paired with the snapshot entry they came from.
    private struct SavedActorValues {
        let entry: WorldStateSnapshotEntry
        let state: ActorValueState
    }

    /// The `AVAL` chunk: every entry with an actor-value component, in key order. Each
    /// repeats its key and cell, because a values-only actor has no `RDLT` entry.
    public static func writeActorValues(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> SavedActorValues? in
            guard let state = entry.delta.component(ActorValueState.self) else { return nil }
            return SavedActorValues(entry: entry, state: state)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.actorValues, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.entry.key, into: &payload)
                writeCell(each.entry.delta.cell, into: &payload)
                // Health, magicka, stamina — `ActorValueKind`'s own order, and
                // the order every other surface in this subsystem uses.
                for kind in ActorValueKind.allCases {
                    payload.writeFloat32(each.state.current[kind])
                }
            }
        }
    }

    /// The `AVOV` chunk: every actor with values off its record baseline. Always beside
    /// `AVAL`, which the decoder needs for current health. Offsets, not values; the
    /// temporary modifier is skipped (`ChunkTag.actorValueOverrides`).
    public static func writeActorValueOverrides(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> SavedActorValues? in
            guard
                let state = entry.delta.component(ActorValueState.self),
                !state.overrides.isEmpty
            else { return nil }
            return SavedActorValues(entry: entry, state: state)
        }
        guard !saved.isEmpty else { return }
        let tag = OpenSkySaveFormat.ChunkTag.actorValueOverrides
        writeChunk(tag: tag, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.entry.key, into: &payload)
                writeCell(each.entry.delta.cell, into: &payload)
                // Ascending index order, so one actor's chunk bytes are a pure
                // function of its state rather than of dictionary iteration.
                let indices = each.state.overrides.keys.sorted()
                payload.writeUInt32(UInt32(clamping: indices.count))
                for index in indices {
                    guard let override = each.state.overrides[index] else { continue }
                    payload.writeUInt32(UInt32(bitPattern: index))
                    payload.writeFloat32(override.baseOffset)
                    payload.writeFloat32(override.permanent)
                    payload.writeFloat32(override.damage)
                }
            }
        }
    }
}
