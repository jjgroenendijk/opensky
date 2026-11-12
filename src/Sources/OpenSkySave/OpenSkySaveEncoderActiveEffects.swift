// AEFF chunk writing. Per effect: sequence, source kind and key, MGEF key, optional
// caster, mode, detrimental byte, duration, elapsed, seconds paid, optional stacking
// keyword, then one record per actor value. `elapsed` is stored, not "remaining", so a
// reload reports the same total duration.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyMagicInterface
public import OpenSkyWorldState

nonisolated enum OpenSkySaveActiveEffectsWriter {
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
        writer.writeChunk(tag: OpenSkySaveFormat.ChunkTag.activeEffects) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                payload.writeKey(each.entry.key)
                payload.writeCell(each.entry.delta.cell)
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
        writer.writeKey(effect.source.record)
        writer.writeKey(effect.effect)
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
        writer.writeKey(key)
    }
}
