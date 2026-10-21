// ENCK chunk: the enchantments the player knows and has made, merged into the `RDLT`
// deltas by key. Made rows ascend by id, so equal state gives equal bytes.
// Layout: docs/formats/opensky-save-actor-chunks.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyMagicInterface
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// The known keys; then per made enchantment its id, name, capacity, cost per use,
    /// and each base key with its power.
    public static func writeEnchanting(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        writeStory(
            EnchantingState.self, tag: OpenSkySaveFormat.ChunkTag.enchanting, entries, &writer
        ) { state, payload in
            payload.writeUInt32(UInt32(clamping: state.known.count))
            for key in state.known {
                writeKey(key, into: &payload)
            }
            let made = state.made.sorted { $0.key.rawValue < $1.key.rawValue }
            payload.writeUInt32(UInt32(clamping: made.count))
            for (id, enchantment) in made {
                payload.writeUInt32(id.rawValue)
                writeString(enchantment.name, into: &payload)
                payload.writeFloat32(enchantment.capacity)
                payload.writeFloat32(enchantment.costPerUse)
                payload.writeUInt32(UInt32(clamping: enchantment.bases.count))
                for (base, power) in zip(enchantment.bases, enchantment.powers) {
                    writeKey(base, into: &payload)
                    payload.writeFloat32(power)
                }
            }
        }
    }
}

nonisolated extension OpenSkySaveStoryDecoder {
    public static func decodeEnchanting(
        _ payload: Data
    ) throws -> [SaveStoryEntry<EnchantingState>] {
        let tag = OpenSkySaveFormat.ChunkTag.enchanting
        return try decode(
            payload, tag: tag, minimumSize: OpenSkySaveFormat.minimumEnchantingEntrySize
        ) { reader in
            let knownCount = try reader.uint32("ENCK known count")
            try check(knownCount, OpenSkySaveFormat.minimumSpellbookKeySize, reader)
            var known: [ReferenceKey] = []
            for _ in 0 ..< knownCount {
                try known.append(OpenSkySaveEntryDecoder.decodeKey(&reader))
            }
            let madeCount = try reader.uint32("ENCK made count")
            try check(madeCount, OpenSkySaveFormat.minimumMadeEnchantmentSize, reader)
            var made: [FormID: MadeEnchantment] = [:]
            for _ in 0 ..< madeCount {
                let id = try FormID(reader.uint32("ENCK made id"))
                made[id] = try decodeMade(&reader)
            }
            return EnchantingState(known: known, made: made)
        }
    }

    private static func decodeMade(_ reader: inout SaveReader) throws -> MadeEnchantment {
        let name = try reader.string("ENCK name")
        let capacity = try reader.float32("ENCK capacity")
        let costPerUse = try reader.float32("ENCK cost per use")
        let count = try reader.uint32("ENCK base count")
        try check(count, OpenSkySaveFormat.minimumSpellbookKeySize + 4, reader)
        var bases: [ReferenceKey] = []
        var powers: [Float] = []
        for _ in 0 ..< count {
            try bases.append(OpenSkySaveEntryDecoder.decodeKey(&reader))
            try powers.append(reader.float32("ENCK power"))
        }
        return MadeEnchantment(
            bases: bases, powers: powers, capacity: capacity, costPerUse: costPerUse, name: name
        )
    }

    private static func check(_ count: UInt32, _ size: Int, _ reader: SaveReader) throws {
        try OpenSkySaveDecoder.validate(
            count: count, minimumElementSize: size, remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.enchanting
        )
    }
}
