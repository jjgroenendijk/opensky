import Foundation
import OpenSkyBehavior
import OpenSkyFormatsESM
import simd

/// A forced flight from agent control, which wins over the fight.
nonisolated public enum DragonFlightOrder: String, Equatable, Sendable {
    case takeOff
    case land
    /// Land on the nearest perch in reach, or hover where none is.
    case perch
    case hastyLand
    case crashLand

    /// Orders that end once the dragon is on the ground or its perch.
    public var endsOnLanding: Bool {
        self != .takeOff
    }
}
