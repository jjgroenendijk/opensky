// The stages of a flying actor's fight: in the air, circling its target; on a perch,
// attacking from range; and on the ground, fighting as any actor does. The stage times
// come from the install and the style's CSFL values; the order is OpenSky's reading
// (docs/engine/combat-behavior.md#flying-combat).

import Foundation
import OpenSkyCombatInterface

nonisolated public struct CombatFlightCycle: Equatable, Sendable {
    nonisolated public enum Stage: String, Equatable, Sendable {
        case air
        case perch
        case ground
    }

    /// A fight starts in the air, where a flying actor is found.
    public private(set) var stage = Stage.air
    public private(set) var stageSeconds: Float = 0

    public init() {}

    /// Moves the stage clock on. An air stage ends on a perch when `roll` (0 to 1) is under
    /// the perch chance, otherwise on the ground; perch and ground stages go back to the air.
    /// - Returns: true on the step the stage changed.
    public mutating func advance(
        seconds: Float, settings: CombatFlightSettings, roll: () -> Float
    ) -> Bool {
        guard seconds.isFinite, seconds > 0 else { return false }
        stageSeconds += seconds
        guard stageSeconds >= duration(of: stage, settings: settings) else { return false }
        switch stage {
        case .air: stage = roll() < settings.perchChance ? .perch : .ground
        case .perch, .ground: stage = .air
        }
        stageSeconds = 0
        return true
    }

    public mutating func reset() {
        self = Self()
    }

    private func duration(of stage: Stage, settings: CombatFlightSettings) -> Float {
        let seconds = switch stage {
        case .air: settings.airSeconds
        case .perch: settings.perchSeconds
        case .ground: settings.groundSeconds
        }
        return seconds.isFinite ? max(seconds, 0) : 0
    }
}
