import Foundation
import OpenSkyFormatsCore

/// How long each measured phase took.
nonisolated public struct SessionStartTiming: Equatable, Sendable {
    public private(set) var durations: [SessionStartPhase: Duration] = [:]

    public init() {}

    /// The phases run one after the other, so the total is their sum.
    public var total: Duration {
        durations.values.reduce(.zero, +)
    }
}

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

nonisolated extension SessionStartTiming {
    public mutating func record(_ phase: SessionStartPhase, _ duration: Duration) {
        durations[phase] = duration
    }

    /// Measured phases in run order.
    public var measured: [(phase: SessionStartPhase, duration: Duration)] {
        SessionStartPhase.allCases.compactMap { phase in
            durations[phase].map { (phase: phase, duration: $0) }
        }
    }
}
