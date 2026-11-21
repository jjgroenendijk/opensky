// A quest start that a script asked for. The game queues it, so the quest passes
// through these phases over two frames or more. See docs/engine/quest-state.md,
// "Starting a quest".

import Foundation

/// How far a queued start has come.
nonisolated public enum QuestStartPhase: UInt8, Equatable, Sendable {
    /// No start waits. The quest is stopped or running.
    case idle = 0
    /// The request waits in the queue. The quest is unchanged.
    case queued = 1
    /// The aliases are filled and the quest is reset. The start-up stages come next.
    case prepared = 2
    /// The start-up stages are set and their fragments run.
    case startUp = 3
}

/// The queued start of one quest, and what waits for it.
nonisolated public struct QuestStartState: Equatable, Sendable {
    public var phase: QuestStartPhase
    /// Position in the queue. A lower number starts first.
    public var order: UInt32
    /// Stages that `SetStage` asked for on the stopped quest, in call order.
    public var stages: [UInt16]
    /// Objectives a script showed on the stopped quest, in call order.
    public var objectives: [UInt16]
    /// A start has succeeded before. A "Run Once" quest then refuses a new start.
    public var hasRun: Bool

    public init(
        phase: QuestStartPhase = .idle, order: UInt32 = 0, stages: [UInt16] = [],
        objectives: [UInt16] = [], hasRun: Bool = false
    ) {
        self.phase = phase
        self.order = order
        self.stages = stages
        self.objectives = objectives
        self.hasRun = hasRun
    }

    /// True when the save has something to keep beyond the flag bits.
    public var hasRequest: Bool {
        phase != .idle
    }
}

nonisolated extension QuestRuntimeState {
    /// `IsRunning()` as a script and a condition see it: false until the start-up
    /// stage fragments have finished.
    public var reportsRunning: Bool {
        isRunning && start.phase == .idle
    }

    /// `IsStarting()`: the aliases are filled and the quest does not run yet.
    public var isStarting: Bool {
        start.phase == .prepared || start.phase == .startUp
    }

    /// `IsStopped()`: a queued request leaves the quest stopped.
    public var reportsStopped: Bool {
        !isRunning && (start.phase == .idle || start.phase == .queued)
    }

    /// True while a queued start has not reached its start-up stages.
    public var awaitsStart: Bool {
        start.phase == .queued || start.phase == .prepared
    }

    /// This state with a start request at queue position `order`. A quest that
    /// already waits keeps its position.
    public func queueingStart(order: UInt32, stage: UInt16?, objective: UInt16?) -> Self {
        var result = self
        if result.start.phase == .idle {
            result.start.phase = .queued
            result.start.order = order
        }
        if let stage {
            result.start.stages.append(stage)
        }
        if let objective, !result.start.objectives.contains(objective) {
            result.start.objectives.append(objective)
        }
        return result
    }

    /// This state with the start done: scripts now see a running quest.
    public func finishingStart() -> Self {
        var result = self
        result.start = QuestStartState(hasRun: true)
        return result
    }

    /// This state with the start request dropped, after a required alias did not fill.
    public func cancellingStart() -> Self {
        var result = self
        result.start = QuestStartState(hasRun: start.hasRun)
        return result
    }

    /// This state with `start` as the save stored it.
    public func restoringStart(_ start: QuestStartState) -> Self {
        var result = self
        result.start = start
        return result
    }
}
