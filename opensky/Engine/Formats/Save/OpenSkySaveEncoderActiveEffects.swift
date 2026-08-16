// AEFF chunk writing for the OpenSky native save container (issue #469).
//
// A satellite of `OpenSkySaveEncoder` for the same reason the AVAL and DETH
// writers are: the encoder is at its type-length limit. The three shared
// writers it uses — `writeChunk`, `writeKey`, `writeCell` — are internal on the
// parent for exactly this reason.
//
// Per effect, in order: the sequence, the source kind, the source record key,
// the MGEF key, an optional caster key, the mode, the detrimental byte, the
// duration, the elapsed seconds, the seconds already paid out, an optional
// stacking keyword, and then one record per actor value the effect acts on.
//
// The layout deliberately stores `elapsed` rather than "remaining": the same
// two numbers describe the effect either way, and keeping duration and elapsed
// separate means a reloaded effect reports the same total duration a readout
// showed before the save.

import Foundation

nonisolated extension OpenSkySaveEncoder {
    /// One actor's effects paired with the snapshot entry they came from.
    private struct SavedActiveEffects {
        let entry: WorldStateSnapshotEntry
        let state: ActiveEffectState
    }

    /// The `AEFF` chunk: every snapshot entry carrying active effects, in the
    /// snapshot's `ReferenceKey` order. A session in which nothing was applied
    /// writes no chunk, so its bytes match what this encoder produced before
    /// the chunk existed.
    static func writeActiveEffects(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> SavedActiveEffects? in
            guard
                let state = entry.delta.component(ActiveEffectState.self),
                !state.isEmpty
            else { return nil }
            return SavedActiveEffects(entry: entry, state: state)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.activeEffects, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.entry.key, into: &payload)
                writeCell(each.entry.delta.cell, into: &payload)
                payload.writeUInt32(UInt32(clamping: each.state.effects.count))
                for effect in each.state.effects {
                    writeActiveEffect(effect, into: &payload)
                }
            }
        }
    }

    private static func writeActiveEffect(_ effect: ActiveEffect, into writer: inout BinaryWriter) {
        writer.writeUInt64(effect.sequence)
        writer.writeUInt32(effect.source.kind.rawValue)
        writeKey(effect.source.record, into: &writer)
        writeKey(effect.effect, into: &writer)
        writeOptionalKey(effect.caster, into: &writer)
        writer.writeUInt32(effect.mode.rawValue)
        writer.writeUInt8(effect.isDetrimental ? 1 : 0)
        writer.writeFloat32(effect.duration)
        writer.writeFloat32(effect.elapsed)
        writer.writeUInt32(effect.paidSeconds)
        writeOptionalKey(effect.stackKeyword, into: &writer)
        writer.writeUInt32(UInt32(clamping: effect.values.count))
        for value in effect.values {
            writer.writeUInt32(UInt32(bitPattern: value.index))
            writer.writeFloat32(value.magnitude)
            writer.writeFloat32(value.applied)
        }
    }

    /// A presence byte then the key, matching how `writeCell` spells "absent".
    private static func writeOptionalKey(_ key: ReferenceKey?, into writer: inout BinaryWriter) {
        guard let key else {
            writer.writeUInt8(0)
            return
        }
        writer.writeUInt8(1)
        writeKey(key, into: &writer)
    }
}
