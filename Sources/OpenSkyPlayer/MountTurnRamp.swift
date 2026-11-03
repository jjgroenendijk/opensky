// A ridden horse turns slowly at first and faster while the turn is held
// (docs/engine/riding.md#steering).

import Foundation

nonisolated public struct MountTurnRamp: Equatable, Sendable {
    /// A wanted turn below this, in radians, counts as no turn: the horse faces its goal.
    public static let turnThreshold: Float = 0.001

    /// Radians a second the horse turns at now.
    public private(set) var rate: Float = 0

    public init() {}

    /// Steps the rate. A held turn raises it by the ramp up to the maximum; the end of
    /// the turn drops it to zero. A paused frame changes nothing. Returns the rate.
    public mutating func advance(
        wantedTurn: Float?, deltaTime: Float, settings: MountSettings
    ) -> Float {
        guard deltaTime.isFinite, deltaTime > 0 else { return rate }
        guard let wantedTurn, abs(wantedTurn) > Self.turnThreshold else {
            rate = 0
            return rate
        }
        rate = min(rate + settings.turnRampUp * deltaTime, settings.turnRate)
        return rate
    }
}
