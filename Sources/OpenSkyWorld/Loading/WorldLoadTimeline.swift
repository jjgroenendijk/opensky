// What a world load has done so far: the state and time of each stage. The
// launcher draws it live, and the developer sidebar shows the last one.

import Foundation

nonisolated public struct WorldLoadTimeline: Equatable, Sendable {
    public enum StageState: Equatable, Sendable {
        case pending
        case running
        case finished(Duration)
    }

    public private(set) var states: [WorldLoadStage: StageState]

    public init() {
        states = Dictionary(uniqueKeysWithValues: WorldLoadStage.allCases.map { ($0, .pending) })
    }

    public mutating func apply(_ event: WorldLoadEvent) {
        switch event.kind {
        case .started:
            states[event.stage] = .running
        case let .finished(duration):
            states[event.stage] = .finished(duration)
        }
    }

    public func state(of stage: WorldLoadStage) -> StageState {
        states[stage] ?? .pending
    }

    public var finishedCount: Int {
        WorldLoadStage.allCases.count { stage in
            guard case .finished = state(of: stage) else { return false }
            return true
        }
    }

    /// From 0 to 1, by finished stage count.
    public var fraction: Double {
        Double(finishedCount) / Double(WorldLoadStage.allCases.count)
    }

    /// The running stages, in list order.
    public var runningStages: [WorldLoadStage] {
        WorldLoadStage.allCases.filter { state(of: $0) == .running }
    }

    /// The finished stages, slowest first.
    public var slowestFirst: [(stage: WorldLoadStage, duration: Duration)] {
        WorldLoadStage.allCases
            .compactMap { stage in
                if case let .finished(duration) = state(of: stage) {
                    (stage, duration)
                } else {
                    nil
                }
            }
            .sorted { $0.duration > $1.duration }
    }
}

nonisolated extension Duration {
    /// Seconds with two decimals, such as `1.25 s`.
    public var secondsText: String {
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return String(format: "%.2f s", seconds)
    }
}
