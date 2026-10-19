// FAVS chunk: the player's favourite items in the order they were marked, then the
// hotkeys by ascending slot. Layout: docs/formats/opensky-save-actor-chunks.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// The item count and FormIDs, then the hotkey count and each slot byte and item.
    public static func writeFavourites(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        writeStory(
            FavouritesState.self, tag: OpenSkySaveFormat.ChunkTag.favourites, entries, &writer
        ) { state, payload in
            payload.writeUInt32(UInt32(clamping: state.items.count))
            for item in state.items {
                payload.writeUInt32(item.rawValue)
            }
            let hotkeys = state.hotkeys.sorted { $0.key < $1.key }
            payload.writeUInt32(UInt32(clamping: hotkeys.count))
            for (slot, item) in hotkeys {
                payload.writeUInt8(UInt8(clamping: slot))
                payload.writeUInt32(item.rawValue)
            }
        }
    }
}

nonisolated extension OpenSkySaveStoryDecoder {
    public static func decodeFavourites(
        _ payload: Data
    ) throws -> [SaveStoryEntry<FavouritesState>] {
        let tag = OpenSkySaveFormat.ChunkTag.favourites
        return try decode(
            payload, tag: tag, minimumSize: OpenSkySaveFormat.minimumFavouritesEntrySize
        ) { reader in
            let count = try reader.uint32("FAVS item count")
            try OpenSkySaveDecoder.validate(
                count: count, minimumElementSize: 4, remaining: reader.bytesRemaining, chunk: tag
            )
            var items: [FormID] = []
            for _ in 0 ..< count {
                try items.append(FormID(reader.uint32("FAVS item")))
            }
            let slots = try reader.uint32("FAVS hotkey count")
            try OpenSkySaveDecoder.validate(
                count: slots, minimumElementSize: OpenSkySaveFormat.favouriteHotkeySize,
                remaining: reader.bytesRemaining, chunk: tag
            )
            var hotkeys: [Int: FormID] = [:]
            for _ in 0 ..< slots {
                let slot = try Int(reader.uint8("FAVS slot"))
                hotkeys[slot] = try FormID(reader.uint32("FAVS hotkey item"))
            }
            return FavouritesState(items: items, hotkeys: hotkeys)
        }
    }
}
