import Foundation

/// Which clock a timer counts against.
nonisolated public enum PapyrusUpdateTimerFamily: Hashable, Sendable {
    case real
    case gameTime
}

/// One of the four per-instance timer slots. The raw value is the stable slot
/// order snapshots sort by.
nonisolated public enum PapyrusUpdateTimerSlot: Int, CaseIterable, Hashable, Sendable {
    case realRepeating = 0
    case realSingleShot = 1
    case gameTimeRepeating = 2
    case gameTimeSingleShot = 3

    public var family: PapyrusUpdateTimerFamily {
        switch self {
        case .realRepeating, .realSingleShot: .real
        case .gameTimeRepeating, .gameTimeSingleShot: .gameTime
        }
    }

    public var isRepeating: Bool {
        self == .realRepeating || self == .gameTimeRepeating
    }
}

/// One persisted timer slot, the unit stage B's save chunk serializes. The
/// delay is stored as time remaining rather than an absolute deadline, so a
/// restore re-anchors against the current clock and the wall or game time
/// spent between save and load never counts toward the timer.
nonisolated public struct PapyrusTimerState: Equatable, Sendable {
    public let key: PapyrusInstanceKey
    public let slot: PapyrusUpdateTimerSlot
    /// Registered interval in the slot's unit: real seconds or game hours.
    public let interval: Double
    /// Time left before the next fire, in the same unit. Never negative.
    public let remaining: Double

    public init(
        key: PapyrusInstanceKey,
        slot: PapyrusUpdateTimerSlot,
        interval: Double,
        remaining: Double
    ) {
        self.key = key
        self.slot = slot
        self.interval = interval
        self.remaining = remaining
    }
}
