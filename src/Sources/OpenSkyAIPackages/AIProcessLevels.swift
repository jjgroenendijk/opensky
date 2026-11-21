// The four AI process levels: which one an actor is in, how often each updates, and the
// time budget a frame gives the slower ones. Pure. See docs/engine/ai-process-levels.md.

import Foundation

nonisolated public enum AIProcessLevel: Int, CaseIterable, Sendable {
    case high, middleHigh, middleLow, low

    public var name: String {
        switch self {
        case .high: "high"
        case .middleHigh: "middle-high"
        case .middleLow: "middle-low"
        case .low: "low"
        }
    }

    /// Game hours between two updates at `TimeScale` 1. Nil for High: every frame.
    public var updateHours: Double? {
        switch self {
        case .high: nil
        case .middleHigh: 0.05
        case .middleLow: 0.15
        case .low: 0.30
        }
    }

    /// Game seconds between two updates of one actor. Nil for High.
    public func updateSeconds(timescale: Float) -> Double? {
        updateHours.map { $0 * 3600 / Double(max(timescale, 1)) }
    }
}

/// What the level of one actor is chosen from.
nonisolated public struct AIProcessFacts: Equatable, Sendable {
    public var has3D = false
    public var isForcedHigh = false
    /// In its worldspace's persistent cell.
    public var inPersistentCell = false
    public var distanceToPlayer: Float = 0
    public var isPlayerMount = false
    public var cellAttached = false
    public var cellLoaded = false

    public init() {}
}

nonisolated public enum AIProcessRule {
    /// 10 exterior cells of 4096 units.
    public static let farDistance: Float = 40960
    /// The time is checked after this many actors.
    public static let actorsPerCheck = 10

    /// The level for one actor. Nil keeps the level it has: the game leaves an actor
    /// with 3D in a cell that is neither attached nor loaded where it is.
    public static func level(_ facts: AIProcessFacts) -> AIProcessLevel? {
        guard facts.has3D || facts.isForcedHigh else {
            return facts.cellLoaded ? .middleLow : .low
        }
        if facts.inPersistentCell, facts.distanceToPlayer > farDistance, !facts.isPlayerMount {
            return .middleLow
        }
        if facts.cellAttached {
            return .high
        }
        return facts.cellLoaded ? .middleHigh : nil
    }

    /// True when an update is due: a first one, one after the interval, or one after the
    /// clock went back.
    public static func isDue(now: Double, last: Double?, interval: Double) -> Bool {
        guard let last, last >= 0 else { return true }
        return now < last || now - last >= interval
    }

    /// The milliseconds a frame gives the middle and low levels: 5 from 30 fps, 0.5 below
    /// 10 fps, and (0.5 + 5) × fps / (10 + 30) between.
    public static func budgetMilliseconds(frameSeconds: Float) -> Double {
        guard frameSeconds > 0 else { return 5 }
        let fps = Double(1 / frameSeconds)
        if fps >= 30 {
            return 5
        }
        if fps < 10 {
            return 0.5
        }
        return (0.5 + 5) * fps / (10 + 30)
    }
}

/// One pass over a level's list, kept across frames: it goes on from the saved place.
nonisolated public struct AIProcessTurn<Actor: Hashable & Sendable>: Sendable {
    public private(set) var waiting: [Actor] = []
    public private(set) var place = 0
    /// Passes that stopped over budget since the start.
    public private(set) var overBudgetCount = 0

    public init() {}

    public var isRunning: Bool {
        place < waiting.count
    }

    public mutating func begin(_ actors: [Actor]) {
        waiting = actors
        place = 0
    }

    /// Updates actors in turn until the list ends or `spent` passes `budget`. The time
    /// is read after every 10 actors.
    public mutating func run(
        budget: Double, spent: () -> Double, update: (Actor) -> Void
    ) {
        var sinceCheck = 0
        while place < waiting.count {
            update(waiting[place])
            place += 1
            sinceCheck += 1
            guard sinceCheck >= AIProcessRule.actorsPerCheck else { continue }
            sinceCheck = 0
            if spent() > budget, place < waiting.count {
                overBudgetCount += 1
                return
            }
        }
    }
}
