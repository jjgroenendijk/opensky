import OpenSkyGameData

nonisolated public enum PlayerDeathPhase: Equatable, Sendable {
    case alive
    case bleedingOut(seconds: Float)
    case dead(seconds: Float)
    /// The reload was asked for; the next load sets the phase back to `alive`.
    case reloading
}

/// What one step of the player's death asks of the app.
nonisolated public enum PlayerDeathCommand: Equatable, Sendable {
    case enterBleedout
    /// Stand up; `restoreHealth` is true when the time ran out first.
    case leaveBleedout(restoreHealth: Bool)
    case die
    case reloadNewestSave
}

/// What the player's death reads each frame.
nonisolated public struct PlayerHealthSample: Equatable, Sendable {
    public var share: Float
    public var isEssential: Bool
    /// The class's kneel ratio, or nil for `fBleedoutDefault`.
    public var bleedoutRatio: Float?

    public init(share: Float, isEssential: Bool, bleedoutRatio: Float? = nil) {
        self.share = share
        self.isEssential = isEssential
        self.bleedoutRatio = bleedoutRatio
    }
}
