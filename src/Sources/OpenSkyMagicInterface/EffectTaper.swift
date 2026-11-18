// The MGEF taper: the effect goes on after its duration, at a weight that falls
// along a curve. See docs/engine/magic.md#tapering.

import Foundation

/// How an effect continues after its duration ends.
nonisolated public struct EffectTaper: Equatable, Hashable, Sendable {
    /// The share of the magnitude at the moment the duration ends.
    public let weight: Float
    /// The exponent of the fall. A negative curve makes the effect grow.
    public let curve: Float
    /// Seconds the effect goes on after its duration.
    public let duration: Float

    public static let none = EffectTaper(weight: 0, curve: 0, duration: 0)

    public init(weight: Float, curve: Float, duration: Float) {
        self.weight = weight.isFinite ? weight : 0
        self.curve = curve.isFinite ? curve : 0
        self.duration = duration.isFinite ? max(0, duration) : 0
    }

    /// The share of the magnitude `seconds` after the duration ended:
    /// `weight * (1 - seconds / duration) ^ curve`. One inside the duration, zero after
    /// the taper.
    public func share(after seconds: Float) -> Float {
        guard seconds > 0 else { return 1 }
        guard duration > 0, seconds < duration else { return 0 }
        let left = 1 - seconds / duration
        let share = weight * (curve == 0 ? 1 : powf(left, curve))
        return share.isFinite ? share : 0
    }
}
