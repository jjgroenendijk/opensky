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
nonisolated public enum DetectionState: String, Equatable, Sendable, CaseIterable {
    /// Nothing perceived, or everything perceived has decayed away.
    case unaware
    /// Something was perceived and there is a position worth investigating.
    case suspicious
    /// The observer has the target.
    case detected
}

/// One observer's regard for one target, and the evidence behind it.
nonisolated public struct DetectionPairState: Equatable, Sendable {
    /// Accumulated awareness, 0 through `detectedLevel`.
    public var level: Float = 0
    /// `level` read against the two thresholds.
    public var state: DetectionState = .unaware
    /// The detection value the last evaluation produced, with its terms.
    public var breakdown: DetectionBreakdown = .none
    /// Distance at the last evaluation, world units.
    public var distance: Float = 0
    /// Whether static collision left the sight line clear at the last
    /// evaluation.
    public var hasLineOfSight = false
    /// Whether the target was inside the view cone at the last evaluation.
    public var isInViewCone = false
    /// Where the target was when it was last perceived — the investigate
    /// position. Held while the observer is suspicious or worse and dropped when
    /// the level decays to nothing, so a stale position can never be walked to.
    /// This is what 16.7 sends an actor to, and what the searching combat state
    /// derives from.
    public var lastKnownPosition: SIMD3<Float>?

    public static let unaware = DetectionPairState()

    /// Whether the observer has detected the target outright.
    public var isDetected: Bool {
        state == .detected
    }
}
