// SPLB chunk writing. Per actor: key, cell, known spells, read books, the two readied
// hands behind presence bytes, and `(power, game day)` spent pairs. `SpellbookState.init`
// sorts every list, so an unchanged spellbook re-encodes identically.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyMagicInterface
public import OpenSkyWorldState

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
        writer.writeChunk(tag: OpenSkySaveFormat.ChunkTag.spellbooks) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                payload.writeKey(each.entry.key)
                payload.writeCell(each.entry.delta.cell)
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
            writer.writeKey(power)
            writer.writeUInt32(UInt32(bitPattern: day))
        }
    }

    private static func writeKeyList(_ keys: [ReferenceKey], into writer: inout BinaryWriter) {
        writer.writeUInt32(UInt32(clamping: keys.count))
        for key in keys {
            writer.writeKey(key)
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
        writer.writeKey(key)
    }
}
