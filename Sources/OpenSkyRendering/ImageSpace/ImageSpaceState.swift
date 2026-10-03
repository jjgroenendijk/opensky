// What the composite pass reads each frame: the resolved baseline, the running
// modifiers, and the debug overrides. Set on the main actor between frames.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct ImageSpaceState: Equatable, Sendable {
    /// Off draws the frame without the composite pass, for an A/B.
    public var passEnabled = true
    public var baseline = BaselineImageSpace.none
    /// Replaces the baseline while set, for a strong-tint check.
    public var forcedBaseline: ResolvedImageSpace?
    public var modifiers = ImageSpaceModifierRuntime()

    public init() {}

    /// The baseline in effect: the forced one, else the resolved one.
    public var effectiveBaseline: ImageSpaceParameters {
        forcedBaseline.map { ImageSpaceParameters($0.record) } ?? baseline.parameters
    }

    /// This frame's values, with every modifier applied.
    public var current: ImageSpaceParameters {
        modifiers.apply(to: effectiveBaseline)
    }
}
