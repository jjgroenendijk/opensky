// Controller rumble from sounds: each frame the levels on the two rumble buses become the
// two motor strengths (docs/engine/sound-mix.md#rumble).

import Foundation

/// The level on each rumble bus this frame: every rumbling sound's send times what the
/// listener hears of it, added up.
nonisolated public struct SoundRumble: Equatable, Sendable {
    public static let silent = Self(small: 0, big: 0)

    /// `fAudioRumbleSmallExponent`, `fAudioRumbleBigExponent`, `fAudioRumblePowerAttackAdj`.
    public static let smallExponent: Float = 0.4
    public static let bigExponent: Float = 0.5
    public static let powerAttackAdjustment: Float = 0.15

    public var small: Float
    public var big: Float

    public init(small: Float, big: Float) {
        self.small = min(max(small, 0), 1)
        self.big = min(max(big, 0), 1)
    }

    /// The motor strengths. A power attack lowers both exponents, so the motors run
    /// stronger. With the game's default dead zones (0) and lerp range (0 to 1) a motor is
    /// the bus level raised to its exponent; a silent bus stays still.
    public func motors(powerAttack: Bool) -> Self {
        let adjustment = powerAttack ? Self.powerAttackAdjustment : 0
        func motor(_ level: Float, _ exponent: Float) -> Float {
            level > 0 ? pow(level, max(exponent - adjustment, 0.01)) : 0
        }
        return Self(small: motor(small, Self.smallExponent), big: motor(big, Self.bigExponent))
    }
}
