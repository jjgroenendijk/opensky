import Foundation
public import OpenSkyWorldInterface

nonisolated extension MountTurnRamp {
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
