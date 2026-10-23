// The readout seam for the timing of the world load and session start of the running session.

/// The stages and total wall time of one finished world load.
nonisolated public struct WorldLoadReport: Equatable, Sendable {
    public let timeline: WorldLoadTimeline
    public let total: Duration

    public init(timeline: WorldLoadTimeline, total: Duration) {
        self.timeline = timeline
        self.total = total
    }
}
