/// The stages and total wall time of one finished world load.
nonisolated public struct WorldLoadReport: Equatable, Sendable {
    public let timeline: WorldLoadTimeline
    public let total: Duration
    /// The app start up to the end of this load.
    public let marks: AppStartMarks

    public init(timeline: WorldLoadTimeline, total: Duration, marks: AppStartMarks = .init()) {
        self.timeline = timeline
        self.total = total
        self.marks = marks
    }
}
