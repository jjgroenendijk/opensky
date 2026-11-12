// PRUL chunk: the session rules scripts switched for the player, on the player's delta.
// Layout: docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyWorldState

nonisolated enum OpenSkySavePlayerRulesWriter {
    /// Standard switches leave no component, so they write no chunk.
    static func writePlayerRules(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        OpenSkySaveStoryWriter.writeStory(
            (PlayerRuleSwitches.self, OpenSkySaveFormat.ChunkTag.playerRules), entries, &writer
        ) { state, payload in
            payload.writeUInt8(state.godMode ? 1 : 0)
            payload.writeUInt8(state.reportsCrime ? 1 : 0)
        }
    }
}

nonisolated extension OpenSkySaveStoryDecoder {
    static func decodePlayerRules(
        _ payload: Data
    ) throws -> [SaveStoryEntry<PlayerRuleSwitches>] {
        try decode(
            payload, tag: OpenSkySaveFormat.ChunkTag.playerRules,
            minimumSize: OpenSkySaveFormat.playerRulesEntrySize
        ) { reader in
            try PlayerRuleSwitches(
                godMode: reader.bool("PRUL god mode"),
                reportsCrime: reader.bool("PRUL reports crime")
            )
        }
    }
}
