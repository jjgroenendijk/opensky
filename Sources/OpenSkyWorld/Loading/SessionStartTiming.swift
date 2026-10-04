// The phases between the end of the world data load and the first drawn frame.
// The World panel lists them after the load stages; Instruments shows them as signposts.

import Foundation
import OSLog

/// One step of the session start, in the order it runs on the main actor.
nonisolated public enum SessionStartPhase: String, CaseIterable, Sendable {
    case renderer
    case systems
    case firstFrame

    public var title: String {
        switch self {
        case .renderer: "Renderer setup"
        case .systems: "Game systems"
        case .firstFrame: "First frame"
        }
    }
}

/// How long each measured phase took.
nonisolated public struct SessionStartTiming: Equatable, Sendable {
    public private(set) var durations: [SessionStartPhase: Duration] = [:]

    public init() {}

    public mutating func record(_ phase: SessionStartPhase, _ duration: Duration) {
        durations[phase] = duration
    }

    /// The phases run one after the other, so the total is their sum.
    public var total: Duration {
        durations.values.reduce(.zero, +)
    }

    /// Measured phases in run order.
    public var measured: [(phase: SessionStartPhase, duration: Duration)] {
        SessionStartPhase.allCases.compactMap { phase in
            durations[phase].map { (phase: phase, duration: $0) }
        }
    }
}

/// Times the session start on the main actor and marks each phase as a signpost.
public final class SessionStartRecorder {
    private static let signposter = OSSignposter(
        subsystem: "nl.jjgroenendijk.opensky", category: "SessionStart"
    )
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky", category: "SessionStart"
    )

    public private(set) var timing = SessionStartTiming()
    private let clock = ContinuousClock()
    private var firstFrameWait: (start: ContinuousClock.Instant, state: OSSignpostIntervalState)?

    public init() {}

    public func measure<Result>(
        _ phase: SessionStartPhase,
        _ body: () throws -> Result
    ) rethrows -> Result {
        let state = Self.signposter.beginInterval("phase", "\(phase.rawValue, privacy: .public)")
        let start = clock.now
        defer {
            timing.record(phase, clock.now - start)
            Self.signposter.endInterval("phase", state)
        }
        return try body()
    }

    /// Starts the first-frame phase; `frameDidDraw()` ends it.
    public func waitForFirstFrame() {
        let state = Self.signposter.beginInterval(
            "phase", "\(SessionStartPhase.firstFrame.rawValue, privacy: .public)"
        )
        firstFrameWait = (clock.now, state)
    }

    /// Ends the first-frame phase once and logs the whole session start.
    public func frameDidDraw() {
        guard let wait = firstFrameWait else { return }
        firstFrameWait = nil
        timing.record(.firstFrame, clock.now - wait.start)
        Self.signposter.endInterval("phase", wait.state)
        let phases = timing.measured.map { "\($0.phase.title) \($0.duration.secondsText)" }
        let summary = "\(timing.total.secondsText): " + phases.joined(separator: ", ")
        Self.logger.notice("[INFO] session start \(summary, privacy: .public)")
    }
}
