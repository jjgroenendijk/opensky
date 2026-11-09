// The first stage of a session: the loaded world, the streamer over it, and the frame
// session. An adapter built over it registers its frame steps and session events as it
// is built (docs/decisions/session-scope.md).

public import OpenSkyCells

public struct SessionStage {
    public let gameSession: GameSession
    public let streamer: CellStreamer
    public let data: WorldDataStores

    public init(gameSession: GameSession, streamer: CellStreamer, data: WorldDataStores) {
        self.gameSession = gameSession
        self.streamer = streamer
        self.data = data
    }
}
