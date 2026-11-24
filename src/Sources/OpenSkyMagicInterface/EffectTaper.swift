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

    /// The mean share over `start ... end` seconds after the duration ended: 1 before it
    /// ended, the curve's integral inside the taper, 0 after. A whole taper then pays
    /// `weight * duration / (curve + 1)` of the magnitude, as UESP gives.
    public func meanShare(from start: Float, to end: Float) -> Float {
        guard end > start else { return share(after: end) }
        var area = max(0, min(end, 0) - start)
        let lower = max(start, 0)
        let upper = min(end, duration)
        if duration > 0, upper > lower {
            area += integral(from: lower, to: upper)
        }
        let mean = area / (end - start)
        return mean.isFinite ? mean : share(after: end)
    }

    /// The integral of the share from `lower` to `upper`, both inside the taper.
    private func integral(from lower: Float, to upper: Float) -> Float {
        let low = 1 - lower / duration
        let high = 1 - upper / duration
        let power = curve + 1
        if abs(power) < 1e-6 {
            return weight * duration * (logf(low) - logf(high))
        }
        return weight * duration / power * (powf(low, power) - powf(high, power))
    }
}
