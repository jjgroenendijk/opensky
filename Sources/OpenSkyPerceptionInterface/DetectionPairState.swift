// What one observer makes of one target: a level that climbs while it perceives
// and decays while it does not, read as three states. A level, not a boolean, so
// the eye opens gradually and a clipped doorway does not flicker (UESP
// "Skyrim:Sneak"). The rates are ours, on `DetectionSettings`. `advance(by:)` is
// pure, so stepping a pair every eighth step gives the same answer as every step.
// See docs/engine/detection.md.

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
