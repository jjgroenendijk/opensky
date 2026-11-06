// The cues the game gives while the player's health is low: a heartbeat sound and a
// pulsing image space modifier (`IMLH`). Pure. See docs/rendering/image-space.md#low-health.

/// Which heartbeat the player's health asks for.
nonisolated public enum Heartbeat: Equatable, Sendable {
    case slow
    case fast
}

/// What the frame must do with the heartbeat sound.
nonisolated public enum HeartbeatChange: Equatable, Sendable {
    /// Stop the one playing at once, then start this one at full volume.
    case start(Heartbeat)
    /// Fade the one playing out over `PlayerHealthCues.heartbeatFadeSeconds`.
    case fadeOut
}

nonisolated public struct PlayerHealthCues: Equatable, Sendable {
    /// `fPlayerHealthHeartbeatSlow`: the slow heartbeat and the pulse start at or below it.
    public static let slowShare: Float = 0.2
    /// `fPlayerHealthHeartbeatFast`.
    public static let fastShare: Float = 0.1
    /// `iPlayerHealthHeartbeatFadeMS`.
    public static let heartbeatFadeSeconds: Float = 1
    /// `fLowHealthIModInterval`, `fLowHealthIModStrengthMin`, `fLowHealthIModStrengthMax`.
    public static let pulseInterval: Float = 2
    public static let weakestPulse: Float = 0.8
    public static let strongestPulse: Float = 1.5

    public var pulseEnabled = true
    public private(set) var heartbeat: Heartbeat?
    private var lastShare: Float?
    public private(set) var pulsing = false
    private var countdown: Float = 0

    public init() {}

    /// Health over its maximum; 1 when there is no maximum.
    public static func share(current: Float, maximum: Float) -> Float {
        maximum > 0 && current.isFinite ? current / maximum : 1
    }

    /// The heartbeat for `share`; none above the slow share and at 0 or below.
    public static func heartbeat(for share: Float) -> Heartbeat? {
        guard share > 0, share <= slowShare else { return nil }
        return share <= fastShare ? .fast : .slow
    }

    /// 0.8 at the slow share up to 1.5 at the fast share and below.
    public static func pulseStrength(share: Float) -> Float {
        let clamped = min(max(share, fastShare), slowShare)
        let along = (slowShare - clamped) / (slowShare - fastShare)
        return weakestPulse + along * (strongestPulse - weakestPulse)
    }

    /// Reads health only when it changed, as the game does. `heartbeatPlaying` is false
    /// once a sound that does not loop has ended, so the next change starts it again.
    public mutating func healthChanged(
        share: Float, heartbeatPlaying: Bool
    ) -> HeartbeatChange? {
        guard share != lastShare else { return nil }
        lastShare = share
        pulsing = pulseEnabled && share <= Self.slowShare ? (pulsing || startPulse()) : false
        let wanted = Self.heartbeat(for: share)
        defer { heartbeat = wanted }
        guard let wanted else { return heartbeat == nil ? nil : .fadeOut }
        return wanted == heartbeat && heartbeatPlaying ? nil : .start(wanted)
    }

    /// The strength of a pulse that starts now, if one does.
    public mutating func advance(_ seconds: Float) -> Float? {
        guard pulsing, seconds > 0, let share = lastShare else { return nil }
        countdown -= seconds
        guard countdown <= 0 else { return nil }
        countdown = Self.pulseInterval
        return Self.pulseStrength(share: share)
    }

    /// A new or loaded game: no heartbeat, no pulse. The switch stays.
    public mutating func reset() {
        let enabled = pulseEnabled
        self = Self()
        pulseEnabled = enabled
    }

    /// The first pulse fires on the next frame.
    private mutating func startPulse() -> Bool {
        countdown = -1
        return true
    }
}
