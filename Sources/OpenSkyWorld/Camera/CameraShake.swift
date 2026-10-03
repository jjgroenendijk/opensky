// `Game.ShakeCamera`: a decaying wobble of the eye. The masters carry no
// fCameraShakeTime, so the default duration and the falloff are OpenSky's
// choice: docs/engine/kill-cam.md#camera-shake.

import Foundation
import simd

nonisolated public struct CameraShake: Equatable, Sendable {
    public static let defaultDuration: Double = 1
    /// Eye travel at full strength, in game units.
    public static let maximumOffset: Float = 6
    /// Beyond this distance from the source the player feels nothing.
    public static let falloffDistance: Float = 2048

    public let strength: Float
    public let duration: Double
    public let startedAt: Double

    /// `strength` is clamped to 0...1; a duration of zero or less uses the default.
    public init(strength: Float, duration: Double, startedAt: Double) {
        self.strength = min(max(strength.isFinite ? strength : 0, 0), 1)
        self.duration = duration > 0 ? duration : Self.defaultDuration
        self.startedAt = startedAt
    }

    /// Strength felt at `distance` from the source: linear to zero at the falloff.
    public static func strength(_ strength: Float, atDistance distance: Float?) -> Float {
        guard let distance else { return strength }
        return strength * max(0, 1 - distance / falloffDistance)
    }

    public func isFinished(at time: Double) -> Bool {
        time - startedAt >= duration
    }

    /// The eye offset at `time`: three sine waves that fade out over the duration.
    public func offset(at time: Double) -> SIMD3<Float> {
        let elapsed = time - startedAt
        guard elapsed >= 0, elapsed < duration, strength > 0 else { return .zero }
        let fade = Float(1 - elapsed / duration)
        let phase = Float(elapsed) * 2 * .pi
        let wave = SIMD3<Float>(sin(phase * 13), sin(phase * 17 + 1.3), sin(phase * 11 + 2.1) * 0.6)
        return wave * Self.maximumOffset * strength * fade
    }
}
