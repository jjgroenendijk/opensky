// AVAL chunk writing for the OpenSky native save container (issue #194).
//
// A satellite of `OpenSkySaveEncoder` for the same reason the INVN and QSTS
// writers are: the encoder is at its type-length limit. The three shared
// writers it uses — `writeChunk`, `writeKey`, `writeCell` — are internal on the
// parent for exactly this reason.
//
// The cell travels with each entry, unlike a quest entry: an actor is a placed
// reference, and its cell is what the store's per-cell dirty counts are keyed
// by.

import Foundation

nonisolated extension OpenSkySaveEncoder {
    /// One actor's values paired with the snapshot entry they came from.
    private struct SavedActorValues {
        let entry: WorldStateSnapshotEntry
        let state: ActorValueState
    }

    /// The `AVAL` chunk: every snapshot entry carrying an actor-value
    /// component, in the snapshot's `ReferenceKey` order. A session in which
    /// nothing took damage writes no chunk, so its bytes match what this
    /// encoder produced before the chunk existed.
    ///
    /// Each entry repeats its key and cell rather than referring back to an
    /// `RDLT` entry by index, because an actor whose only delta is its values
    /// has no `RDLT` entry at all.
    static func writeActorValues(
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

    /// The `AVOV` chunk (issue #496): every actor holding an actor value away
    /// from the baseline its records author, and the overrides it holds.
    ///
    /// Written beside `AVAL` and never instead of it: an actor with an override
    /// has an `ActorValueState` component, so `AVAL` always carries its
    /// primaries' current values, and the decoder relies on that to know what
    /// an actor's health was rather than inventing a zero for it.
    ///
    /// Offsets, not values — see `ChunkTag.actorValueOverrides` for what that
    /// buys and why the temporary modifier is not written.
    static func writeActorValueOverrides(
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
