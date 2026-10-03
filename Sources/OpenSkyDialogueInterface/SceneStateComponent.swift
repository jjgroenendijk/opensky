// A playing scene as a world-state component, keyed by the SCEN record's
// `ReferenceKey`. A stopped scene has no component: "not playing" is the
// baseline. See docs/engine/scenes.md.

import Foundation
import OpenSkyWorldState

nonisolated public struct SceneRuntimeState: WorldStateComponent, Sendable {
    /// The phase the scene is in, 0-based.
    public var phase: UInt32
    /// The phase passed its start conditions and its actions began.
    public var phaseEntered: Bool
    /// Actions, by index in the SCEN action list, that started and have not ended.
    public var running: [SceneActionProgress]
    /// Actions that ended in the current scene run.
    public var completed: [UInt32]

    public static var componentKind: WorldStateComponentKind {
        .scene
    }

    public init(
        phase: UInt32 = 0,
        phaseEntered: Bool = false,
        running: [SceneActionProgress] = [],
        completed: [UInt32] = []
    ) {
        self.phase = phase
        self.phaseEntered = phaseEntered
        self.running = running.sorted { $0.action < $1.action }
        self.completed = Array(Set(completed)).sorted()
    }

    public func isRunning(_ action: UInt32) -> Bool {
        running.contains { $0.action == action }
    }
}

/// One started action: when it started and how long it lasts. A start time, not
/// an elapsed time, so a running scene writes the store only when it changes.
nonisolated public struct SceneActionProgress: Equatable, Sendable {
    public let action: UInt32
    /// Scene seconds at the start: game seconds divided by the time scale.
    public let startedAt: Double
    /// Seconds after which it completes. Nil: it waits for its phase to end.
    public let duration: Float?

    public init(action: UInt32, startedAt: Double, duration: Float?) {
        self.action = action
        self.startedAt = startedAt
        self.duration = duration
    }

    public func isDone(at now: Double) -> Bool {
        guard let duration else { return false }
        return now - startedAt >= Double(duration)
    }
}

nonisolated extension WorldStateComponentKind {
    /// A playing scene. Keyed by the SCEN base record, which is in no cell.
    public static let scene = Self(rawValue: "scene", order: 22, affectsCellBuild: false)
}
