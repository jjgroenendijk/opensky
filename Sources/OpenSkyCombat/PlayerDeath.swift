// The player at zero health: an essential player kneels in bleedout, any other player
// dies, and `fPlayerDeathReloadTime` later the newest save loads. The order of the
// message and the load is OpenSky's reading (docs/engine/ragdoll.md#player-death).

import OpenSkyGameData

/// The texts of the player's death and of bleedout.
nonisolated public enum PlayerDeathText: String, GameSettingTextKey {
    case reloading = "sMiscPlayerDeadMessage"
    case loadOption = "sMiscPlayerDeadLoadOption"
    case menuOption = "sMiscPlayerDeadMenuOption"
    case bleedingOut = "sBleedingOutMessage"
    /// Follows an actor's name: "Lydia is badly wounded."
    case essentialDown = "sEssentialCharacterDown"

    public var fallback: String {
        switch self {
        case .reloading: "Reloading the most recent save game"
        case .loadOption: "Reload"
        case .menuOption: "Main Menu"
        case .bleedingOut: "You can't continue fighting."
        case .essentialDown: "is badly wounded."
        }
    }
}

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

nonisolated public struct PlayerDeath: Equatable, Sendable {
    public private(set) var phase = PlayerDeathPhase.alive
    public let settings: DeathSettings

    public init(settings: DeathSettings = .vanilla) {
        self.settings = settings
    }

    public var isDead: Bool {
        switch phase {
        case .dead, .reloading: true
        case .alive, .bleedingOut: false
        }
    }

    public var isBleedingOut: Bool {
        if case .bleedingOut = phase {
            return true
        }
        return false
    }

    /// What a hit on the kneeling player keeps; 1 otherwise.
    public var incomingDamageMult: Float {
        isBleedingOut ? max(settings.playerBleedoutDamageMult, 0) : 1
    }

    /// A load put the player back in the world.
    public mutating func reset() {
        phase = .alive
    }

    public mutating func advance(
        by delta: Float,
        health: PlayerHealthSample
    ) -> [PlayerDeathCommand] {
        let step = delta.isFinite ? max(delta, 0) : 0
        switch phase {
        case .alive:
            guard health.share <= 0 else { return [] }
            phase = health.isEssential ? .bleedingOut(seconds: 0) : .dead(seconds: 0)
            return health.isEssential ? [.enterBleedout] : [.die]
        case let .bleedingOut(seconds):
            let knelt = seconds + step
            let ratio = health.bleedoutRatio ?? settings.bleedoutThreshold
            let healed = knelt >= settings.bleedoutMinSeconds
                && health.share >= ratio + settings.bleedoutRecoverMargin
            guard healed || knelt >= settings.bleedoutSeconds else {
                phase = .bleedingOut(seconds: knelt)
                return []
            }
            phase = .alive
            return [.leaveBleedout(restoreHealth: !healed)]
        case let .dead(seconds):
            let waited = seconds + step
            guard waited >= settings.playerReloadSeconds else {
                phase = .dead(seconds: waited)
                return []
            }
            phase = .reloading
            return [.reloadNewestSave]
        case .reloading:
            return []
        }
    }
}
