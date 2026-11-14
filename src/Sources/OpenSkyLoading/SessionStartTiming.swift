// The phases between the end of the world data load and the first drawn frame.
// The World readout lists them after the load stages; Instruments shows them as signposts.

public import Foundation
import OpenSkyFormatsCore
public import OpenSkyWorldInterface
import OSLog

/// Times the session start on the main actor and marks each phase as a signpost.
public final class SessionStartRecorder {
    private static let signposter = OSSignposter(
        subsystem: "nl.jjgroenendijk.opensky", category: "SessionStart"
    )
    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky", category: "SessionStart"
    )

    public private(set) var timing = SessionStartTiming()
    private var firstFrameWait: (start: Stopwatch, state: OSSignpostIntervalState)?
    /// The wall clock the start and first-frame marks read.
    private let wallClock: () -> Date

    public init(wallClock: @escaping () -> Date) {
        self.wallClock = wallClock
    }

    public func measure<Result>(
        _ phase: SessionStartPhase,
        _ body: () throws -> Result
    ) rethrows -> Result {
        let state = Self.signposter.beginInterval("phase", "\(phase.rawValue, privacy: .public)")
        timing.startedAt = timing.startedAt ?? wallClock()
        let start = Stopwatch()
        defer {
            timing.record(phase, start.elapsed)
            Self.signposter.endInterval("phase", state)
        }
        return try body()
    }

    /// Starts the first-frame phase; `frameDidDraw()` ends it.
    public func waitForFirstFrame() {
        let state = Self.signposter.beginInterval(
            "phase", "\(SessionStartPhase.firstFrame.rawValue, privacy: .public)"
        )
        firstFrameWait = (Stopwatch(), state)
    }

    /// Ends the first-frame phase once and logs the whole session start.
    public func frameDidDraw() {
        guard let wait = firstFrameWait else { return }
        firstFrameWait = nil
        timing.record(.firstFrame, wait.start.elapsed)
        timing.firstFrameAt = wallClock()
        Self.signposter.endInterval("phase", wait.state)
        let phases = timing.measured.map { "\($0.phase.title) \($0.duration.secondsText)" }
        let summary = "\(timing.total.secondsText): " + phases.joined(separator: ", ")
        Self.logger.notice("[INFO] session start \(summary, privacy: .public)")
    }
}
