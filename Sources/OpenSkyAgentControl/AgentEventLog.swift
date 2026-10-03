// Game events for `openskycli game events`: a bounded ring of recent events, so
// a client that connects late still sees what just happened.

import Foundation

/// The event kinds the app emits. A filter names these strings.
nonisolated public enum AgentEventKind {
    public static let cellLoaded = "cell.loaded"
    public static let cellUnloaded = "cell.unloaded"
    public static let activation = "activation"
    public static let activationRefused = "activation.refused"
    public static let menuOpened = "menu.opened"
    public static let menuClosed = "menu.closed"
    public static let combatHit = "combat.hit"
    public static let actorDeath = "actor.death"
    public static let questStage = "quest.stage"
    public static let scriptError = "script.error"
    public static let log = "log"
    public static let paused = "time.paused"
    public static let resumed = "time.resumed"

    public static let all = [
        cellLoaded, cellUnloaded, activation, activationRefused, menuOpened, menuClosed,
        combatHit, actorDeath, questStage, scriptError, log, paused, resumed
    ]
}

nonisolated public struct AgentEvent: Codable, Equatable, Sendable {
    /// Grows by one per event for the life of the app, never reused.
    public var seq: Int
    public var frame: Int
    public var kind: String
    public var data: [String: AgentJSON]

    public init(seq: Int, frame: Int, kind: String, data: [String: AgentJSON] = [:]) {
        self.seq = seq
        self.frame = frame
        self.kind = kind
        self.data = data
    }
}

nonisolated public struct AgentEventLog: Sendable {
    public let capacity: Int
    public private(set) var events: [AgentEvent] = []
    /// The newest event's `seq`, or 0 before the first one.
    public private(set) var lastSeq = 0

    public init(capacity: Int = 512) {
        self.capacity = max(capacity, 1)
    }

    @discardableResult
    public mutating func append(
        kind: String,
        frame: Int,
        data: [String: AgentJSON] = [:]
    ) -> AgentEvent {
        lastSeq += 1
        let event = AgentEvent(seq: lastSeq, frame: frame, kind: kind, data: data)
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
        return event
    }

    /// Events newer than `seq`, oldest first, optionally limited to `kinds`.
    public func events(after seq: Int, kinds: Set<String> = []) -> [AgentEvent] {
        events.filter { $0.seq > seq && (kinds.isEmpty || kinds.contains($0.kind)) }
    }
}
