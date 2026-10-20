// Stealth points: one pool per target, like hit points for staying hidden. The
// highest detection value of any hostile observer drains it; it refills after a
// wait. At 0 the target is detected; until the pool is full, any positive value
// detects it again.
// CK wiki "Stealth Points" (<https://ck.uesp.net/wiki/Stealth_Points>). See
// docs/engine/detection.md.

import OpenSkyGameData

/// The `fCombatStealthPoint*` and `iCombatStealthPoint*` settings. Defaults are the
/// CK wiki's Category:Settings values; `Skyrim.esm` sets the same where it sets one.
nonisolated public struct StealthPointSettings: Equatable, Sendable {
    /// `fCombatStealthPointMax`.
    public var maximum: Float = 100
    /// `fCombatStealthPointDrainMult`: points lost per second per point of detection.
    public var drainMult: Float = 3
    /// `fCombatStealthPointRegenMin`: points gained per second at a detection of 0.
    public var regenMin: Float = 5
    /// `fCombatStealthPointRegenMult`: extra points per second per point below 0.
    public var regenMult: Float = 0.2
    /// `fCombatStealthPointRegenAlertWaitTime`: seconds without a positive detection
    /// before the pool refills.
    public var refillWait: Float = 10
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
    /// The pool ran out and has not refilled yet: observers that perceive the target,
    /// or detected it before, detect it.
    public private(set) var isExposed = false

    public init(settings: StealthPointSettings = .vanilla) {
        points = max(0, settings.maximum)
    }

    /// One step. `highestValue` is the highest detection value of any observer, and
    /// `overThreshold` says whether one passed the instant-detection threshold.
    public mutating func advance(
        highestValue: Float, overThreshold: Bool, by seconds: Float,
        settings: StealthPointSettings
    ) {
        guard seconds.isFinite, seconds > 0 else { return }
        let maximum = max(0, settings.maximum)
        if overThreshold {
            points = 0
        }
        if highestValue > 0 {
            points = max(0, points - highestValue * max(0, settings.drainMult) * seconds)
            refillWait = max(0, settings.refillWait)
        } else if refillWait > 0 {
            refillWait = max(0, refillWait - seconds)
        } else {
            let rate = max(0, settings.regenMin) + max(0, settings.regenMult) * -highestValue
            points = min(maximum, points + rate * seconds)
        }
        if points <= 0 {
            isExposed = true
        } else if points >= maximum {
            isExposed = false
        }
    }

    /// Whether one observer detects the target now. `value` is its detection value
    /// and `wasDetected` its state before this step. Once the alert wait ends the
    /// observer loses the target and searches while the pool refills.
    public func detects(
        value: Float, isSneaking: Bool, wasDetected: Bool, settings: StealthPointSettings
    ) -> Bool {
        if value >= settings.threshold(isSneaking: isSneaking) {
            return true
        }
        return isExposed && (value > 0 || (wasDetected && refillWait > 0))
    }
}
