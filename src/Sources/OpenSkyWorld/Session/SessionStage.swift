// The first stage of a session: the loaded world, the streamer over it, and the frame
// session. An adapter built over it registers its frame steps and session events as it
// is built (docs/decisions/session-scope.md).

public import OpenSkyCells

/// The stage every adapter is built over.
public typealias SessionStage = SessionStageParts<GameSession>

/// Generic over the session, so a test without Metal 4 can build one over a stand-in.
public struct SessionStageParts<Session: AnyObject> {
    public let gameSession: Session
    public let streamer: CellStreamer
    public let data: WorldDataStores

    public init(gameSession: Session, streamer: CellStreamer, data: WorldDataStores) {
        self.gameSession = gameSession
        self.streamer = streamer
        self.data = data
    }
}
