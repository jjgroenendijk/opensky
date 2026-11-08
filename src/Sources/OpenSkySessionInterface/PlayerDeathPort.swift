public import OpenSkyCombatInterface

/// What the world adapters use of `PlayerDeath`.
public protocol PlayerDeathPort {
    var incomingDamageMult: Float { get }
    var isBleedingOut: Bool { get }
    var phase: PlayerDeathPhase { get }
}
