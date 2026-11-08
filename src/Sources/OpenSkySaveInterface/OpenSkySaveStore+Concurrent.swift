import Foundation
import OpenSkyGameData
public import OpenSkyScriptingInterface
public import OpenSkyWorldState

/// Everything one save writes, taken on the main actor in one frame so it is consistent.
nonisolated public struct OpenSkySaveContents: Sendable {
    public let snapshot: WorldStateSnapshot
    public let metadata: SaveCreationMetadata
    public let clock: GameClock?
    public let scripts: [PapyrusInstanceState]
    public let timers: [PapyrusTimerState]
    public let summary: SaveSummary?
    public let thumbnail: SaveThumbnail?
    public let playerPlace: SavePlayerPlace?

    public init(
        snapshot: WorldStateSnapshot,
        metadata: SaveCreationMetadata,
        clock: GameClock? = nil,
        scripts: [PapyrusInstanceState] = [],
        timers: [PapyrusTimerState] = [],
        summary: SaveSummary? = nil,
        thumbnail: SaveThumbnail? = nil,
        playerPlace: SavePlayerPlace? = nil
    ) {
        self.snapshot = snapshot
        self.metadata = metadata
        self.clock = clock
        self.scripts = scripts
        self.timers = timers
        self.summary = summary
        self.thumbnail = thumbnail
        self.playerPlace = playerPlace
    }
}
