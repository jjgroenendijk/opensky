// Stealth points: one pool per target, like hit points for staying hidden. The
// highest detection value of any hostile observer drains it; it refills after a
// wait. At 0 the target is detected (`CombatTargetTrack`).
// CK wiki "Stealth Points" (<https://ck.uesp.net/wiki/Stealth_Points>). See
// docs/engine/detection.md.

public import OpenSkyGameData

/// The `fCombatStealthPoint*` and `iCombatStealthPoint*` settings. Defaults are the
/// CK wiki's Category:Settings values; `Skyrim.esm` sets the same where it sets one.
nonisolated public struct StealthPointSettings: Equatable, Sendable {
    /// `fCombatStealthPointMax`.
    public var maximum: Float = 100
    /// `fCombatStealthPointDrainMult`: points lost per second per point of detection.
    public var drainMult: Float = 3
    /// `fCombatStealthPointRegenMin`: points gained per second at a detection of 0.
    public var regenMin: Float = 5
    /// `fCombatStealthPointRegenMult`: points per second per point below 0, when more.
    public var regenMult: Float = 0.2
    /// `fCombatStealthPointRegenAlertWaitTime`: seconds without a positive detection
    /// before the pool refills.
    public var refillWait: Float = 10
    /// `fCombatStealthPointRegenAttackedWaitTime`: the wait after the target strikes
    /// an aggressive observer.
    public var attackedWait: Float = 15
    /// `fCombatStealthPointRegenDetectedEventWaitTime`: the wait after an aggressive
    /// observer perceives a detection event of the target, such as an arrow landing.
    public var detectedEventWait: Float = 10
    /// `iCombatStealthPointDetectionThreshold`: a detection value at or above this
    /// detects a standing target at once, whatever the pool holds.
    public var detectionThreshold: Float = 25
    /// `iCombatStealthPointSneakDetectionThreshold`, the same for a sneaking target.
    public var sneakDetectionThreshold: Float = 70

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fCombatStealthPointMax", into: &settings, \.maximum)
        store.read("fCombatStealthPointDrainMult", into: &settings, \.drainMult)
        store.read("fCombatStealthPointRegenMin", into: &settings, \.regenMin)
        store.read("fCombatStealthPointRegenMult", into: &settings, \.regenMult)
        store.read("fCombatStealthPointRegenAlertWaitTime", into: &settings, \.refillWait)
        store.read(
            "fCombatStealthPointRegenAttackedWaitTime", into: &settings, \.attackedWait
        )
        store.read(
            "fCombatStealthPointRegenDetectedEventWaitTime",
            into: &settings, \.detectedEventWait
        )
        store.read(
            "iCombatStealthPointDetectionThreshold", into: &settings, \.detectionThreshold
        )
        store.read(
            "iCombatStealthPointSneakDetectionThreshold",
            into: &settings, \.sneakDetectionThreshold
        )
        return settings
    }

    public func threshold(isSneaking: Bool) -> Float {
        isSneaking ? sneakDetectionThreshold : detectionThreshold
    }
}

/// One target's stealth points.
nonisolated public struct StealthPointPool: Equatable, Sendable {
    public private(set) var points: Float
    /// Seconds left before the pool may refill.
    public private(set) var refillWait: Float = 0
    public init(settings: StealthPointSettings = .vanilla) {
        points = max(0, settings.maximum)
    }

    /// One step. `highestValue` is the highest detection value of any observer, and
    /// `overThreshold` says whether one passed the instant-detection threshold. The
    /// pool refills only while `mayRefill` holds: the game refills a lost target only.
    public mutating func advance(
        highestValue: Float, overThreshold: Bool, by seconds: Float,
        settings: StealthPointSettings, mayRefill: Bool = true
    ) {
        guard seconds.isFinite, seconds > 0 else { return }
        let maximum = max(0, settings.maximum)
        if overThreshold {
            points = 0
        }
        if highestValue > 0 {
            points = max(0, points - highestValue * max(0, settings.drainMult) * seconds)
            refillWait = max(refillWait, settings.refillWait, 0)
        } else if !mayRefill {
            return
        } else if refillWait > 0 {
            refillWait = max(0, refillWait - seconds)
        } else {
            let rate = max(0, settings.regenMin, settings.regenMult * -highestValue)
            points = min(maximum, points + rate * seconds)
        }
    }

    /// Holds the refill for at least `seconds`, as an attack or a detection event does.
    public mutating func holdRefill(for seconds: Float) {
        guard seconds.isFinite else { return }
        refillWait = max(refillWait, seconds)
    }

    /// Lowers the points to `limit`, as a hit by the target or a detection event does.
    public mutating func cap(at limit: Float) {
        guard limit.isFinite else { return }
        points = min(points, max(0, limit))
    }
}
