// What one observer currently makes of one target (issue #202, roadmap item
// 16.6): a level that climbs while something is being perceived and decays
// while nothing is, the three states that level is read as, and the position an
// alerted actor would go and look at.
//
// ## Why a level and not a boolean
//
// Detection in vanilla is described as "an entire system of Stealth Points,
// like hit points but for stealth" (UESP "Skyrim:Sneak"), and every visible
// behaviour depends on that continuity: the eye opening gradually, a guard
// glancing over and going back to work, an alerted guard spotting you faster
// the second time. A boolean recomputed per frame gives none of that and
// flickers on every doorway the sight line clips.
//
// The rates are OpenSky's — no record documents vanilla's — so they are named
// constants on `DetectionSettings` rather than literals here.
//
// ## Determinism
//
// `advance(by:)` is a pure function of the previous state, the inputs and the
// elapsed seconds. It never reads a clock and never samples anything, so the
// same sequence of steps always produces the same level. That is what lets the
// runtime evaluate a pair every eighth step, hand it the elapsed time since it
// was last looked at, and get the same answer as if it had run every step.
//
// Documented in docs/engine/detection.md.

import Foundation
import simd

/// How aware one observer is of one target.
nonisolated enum DetectionState: String, Equatable, Sendable, CaseIterable {
    /// Nothing perceived, or everything perceived has decayed away.
    case unaware
    /// Something was perceived and there is a position worth investigating.
    case suspicious
    /// The observer has the target.
    case detected
}

/// One observer's regard for one target, and the evidence behind it.
nonisolated struct DetectionPairState: Equatable, Sendable {
    /// Accumulated awareness, 0 through `detectedLevel`.
    var level: Float = 0
    /// `level` read against the two thresholds.
    var state: DetectionState = .unaware
    /// The detection value the last evaluation produced, with its terms.
    var breakdown: DetectionBreakdown = .none
    /// Distance at the last evaluation, world units.
    var distance: Float = 0
    /// Whether static collision left the sight line clear at the last
    /// evaluation.
    var hasLineOfSight = false
    /// Whether the target was inside the view cone at the last evaluation.
    var isInViewCone = false
    /// Where the target was when it was last perceived — the investigate
    /// position. Held while the observer is suspicious or worse and dropped when
    /// the level decays to nothing, so a stale position can never be walked to.
    /// This is what 16.7 sends an actor to, and what the searching combat state
    /// derives from.
    var lastKnownPosition: SIMD3<Float>?

    static let unaware = DetectionPairState()

    /// Whether the observer has detected the target outright.
    var isDetected: Bool {
        state == .detected
    }

    /// One step of accumulation or decay.
    ///
    /// - Parameters:
    ///   - inputs: the pair's geometry and the target's movement this instant.
    ///   - targetPosition: where the target is, recorded as the investigate
    ///     position whenever anything is perceived.
    ///   - seconds: elapsed simulated time since this pair was last advanced.
    ///     Zero or non-finite leaves the state alone rather than dividing by it.
    ///   - settings: rates and thresholds.
    func advanced(
        inputs: DetectionInputs,
        targetPosition: SIMD3<Float>,
        by seconds: Float,
        settings: DetectionSettings
    ) -> DetectionPairState {
        let breakdown = DetectionFormula.breakdown(inputs: inputs, settings: settings)
        var updated = self
        updated.breakdown = breakdown
        updated.distance = inputs.distance
        updated.hasLineOfSight = inputs.hasLineOfSight
        updated.isInViewCone = inputs.isInViewCone
        guard seconds.isFinite, seconds > 0 else { return updated }

        let ceiling = max(0, settings.detectedLevel.value)
        if breakdown.isPerceiving {
            let full = max(Float.leastNormalMagnitude, settings.fullDetectionValue.value)
            let rate = min(1, breakdown.value / full) * max(0, settings.gainPerSecond.value)
            updated.level = min(ceiling, level + rate * seconds)
            updated.lastKnownPosition = targetPosition
        } else {
            updated.level = max(0, level - max(0, settings.decayPerSecond.value) * seconds)
            if updated.level <= 0 {
                updated.lastKnownPosition = nil
            }
        }
        updated.state = Self.classify(level: updated.level, settings: settings)
        return updated
    }

    /// The state a level reads as. `detected` needs the full level, so an
    /// observer is only ever certain at the top of the scale.
    static func classify(level: Float, settings: DetectionSettings) -> DetectionState {
        if level >= max(0, settings.detectedLevel.value) {
            return .detected
        }
        return level >= max(0, settings.suspiciousLevel.value) ? .suspicious : .unaware
    }
}
