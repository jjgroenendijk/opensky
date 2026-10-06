// Whether the player may fast travel, and how much game time a trip costs.
// Each refusal names the game setting whose text vanilla shows.
// See docs/engine/world-map.md.

import Foundation

nonisolated public enum FastTravelRefusal: String, Equatable, Sendable, CaseIterable {
    case combat = "sNoFastTravelCombat"
    case hostileActorsNear = "sNoFastTravelHostileActorsNear"
    case overencumbered = "sNoFastTravelOverencumbered"
    case inAir = "sNoFastTravelInAir"
    case alarm = "sNoFastTravelAlarm"
    /// The worldspace or cell has its "no fast travel" flag.
    case noFastTravelHere = "sNoFastTravelCell"
    case scriptBlock = "sNoFastTravelScriptBlock"
    case undiscovered = "sNoFastTravelUndiscovered"
}

nonisolated public struct FastTravelContext: Equatable, Sendable {
    public var inCombat = false
    public var hostilesNear = false
    public var overencumbered = false
    public var inAir = false
    public var alarmed = false
    public var locationForbidsFastTravel = false
    public var enabledByScripts = true
    public var destinationCanTravelTo = true

    public init() {}
}

nonisolated public enum FastTravelRule {
    /// The first reason the trip is refused, in vanilla's order of checks as far
    /// as OpenSky knows it, or nil when it is allowed.
    public static func refusal(_ context: FastTravelContext) -> FastTravelRefusal? {
        if !context.enabledByScripts {
            return .scriptBlock
        }
        if !context.destinationCanTravelTo {
            return .undiscovered
        }
        if context.locationForbidsFastTravel {
            return .noFastTravelHere
        }
        if context.inCombat {
            return .combat
        }
        if context.hostilesNear {
            return .hostileActorsNear
        }
        if context.alarmed {
            return .alarm
        }
        if context.inAir {
            return .inAir
        }
        if context.overencumbered {
            return .overencumbered
        }
        return nil
    }

    /// The game refuses once the carried weight passes the `CarryWeight` actor value.
    public static func isOverencumbered(carried: Float, capacity: Float?) -> Bool {
        guard let capacity else { return false }
        return carried > capacity
    }

    /// Game seconds the trip takes: the straight line walked at `walkSpeed` units per
    /// second, sped up by `fFastTravelSpeedMult`, in game time at `timeScale`. Fitted to
    /// measured trips in docs/engine/world-map.md.
    public static func gameSeconds(
        distance: Float, walkSpeed: Float, speedMultiplier: Float, timeScale: Float
    ) -> Double {
        guard distance > 0, walkSpeed > 0, speedMultiplier > 0, timeScale > 0 else { return 0 }
        return Double(distance / (walkSpeed * speedMultiplier)) * Double(timeScale)
    }
}
