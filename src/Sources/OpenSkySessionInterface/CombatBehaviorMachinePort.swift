public import OpenSkyCombatInterface

/// What the world adapters use of `CombatBehaviorMachine`.
public protocol CombatBehaviorMachinePort {
    var flight: CombatFlightCycle { get }
    var phase: CombatBehaviorPhase { get }
    var settings: CombatBehaviorSettings { get }
}
