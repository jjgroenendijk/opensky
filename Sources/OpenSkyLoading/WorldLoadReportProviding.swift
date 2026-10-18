// The panel seam for the timing of the world load and session start of the running session.

/// The stages and total wall time of one finished world load.
nonisolated public struct WorldLoadReport: Equatable, Sendable {
    public let timeline: WorldLoadTimeline
    public let total: Duration

    public init(timeline: WorldLoadTimeline, total: Duration) {
        self.timeline = timeline
        self.total = total
    }
}

public protocol WorldLoadReportProviding: AnyObject {
    /// Nil when the session started without game data, so nothing loaded.
    var worldLoadReport: WorldLoadReport? { get }
    /// The phases from the end of the load to the first frame; empty without a session.
    var sessionStartTiming: SessionStartTiming { get }
}
