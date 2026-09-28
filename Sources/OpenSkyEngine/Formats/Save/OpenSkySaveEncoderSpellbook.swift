// SPLB chunk writing for the OpenSky native save container (issue #470).
//
// A satellite of `OpenSkySaveEncoder` for the same reason the AEFF, AVAL and
// DETH writers are: the encoder is at its type-length limit. The three shared
// writers it uses — `writeChunk`, `writeKey`, `writeCell` — are internal on the
// parent for exactly this reason.
//
// Per actor, in order: the key, the cell, the known-spell list, the read-book
// list, the two readied hands each behind a presence byte, and the spent-power
// list as `(power, whole game day)` pairs.
//
// Every list is written in the component's own ascending key order, which
// `SpellbookState.init` establishes, so re-encoding an unchanged spellbook
// produces identical bytes.

import Foundation

nonisolated extension OpenSkySaveEncoder {
    /// One actor's spellbook paired with the snapshot entry it came from.
    private struct SavedSpellbook {
        let entry: WorldStateSnapshotEntry
        let state: SpellbookState
    }

    /// The `SPLB` chunk: every snapshot entry carrying a spellbook, in the
    /// snapshot's `ReferenceKey` order. A session in which nobody learned
    /// anything writes no chunk.
    static func writeSpellbooks(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> SavedSpellbook? in
            guard
                let state = entry.delta.component(SpellbookState.self),
                !state.isEmpty
            else { return nil }
            return SavedSpellbook(entry: entry, state: state)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.spellbooks, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.entry.key, into: &payload)
                writeCell(each.entry.delta.cell, into: &payload)
                writeSpellbook(each.state, into: &payload)
            }
        }
    }

    private static func writeSpellbook(_ state: SpellbookState, into writer: inout BinaryWriter) {
        writeKeyList(state.known, into: &writer)
        writeKeyList(state.readBooks, into: &writer)
        writeOptionalSpellKey(state.leftHand, into: &writer)
        writeOptionalSpellKey(state.rightHand, into: &writer)
        let powers = state.powerDays.sorted { $0.key < $1.key }
        writer.writeUInt32(UInt32(clamping: powers.count))
        for (power, day) in powers {
            writeKey(power, into: &writer)
            writer.writeUInt32(UInt32(bitPattern: day))
        }
    }

    private static func writeKeyList(_ keys: [ReferenceKey], into writer: inout BinaryWriter) {
        writer.writeUInt32(UInt32(clamping: keys.count))
        for key in keys {
            writeKey(key, into: &writer)
        }
    }

    /// A presence byte then the key, matching how `writeCell` spells "absent".
    private static func writeOptionalSpellKey(
        _ key: ReferenceKey?,
        into writer: inout BinaryWriter
    ) {
        guard let key else {
            writer.writeUInt8(0)
            return
        }
        writer.writeUInt8(1)
        writeKey(key, into: &writer)
    }
}
