// What the behavior evaluator could not evaluate. An unknown class still returns a
// pose and adds one entry, so the tally is the coverage evidence the real-data probe
// reads. Name tables are capped; totals keep counting past the cap.

import Foundation

/// Counts of everything one behavior graph instance could not evaluate, plus
/// the volume it did evaluate.
nonisolated public struct BehaviorTally: Equatable, Sendable {
    /// Distinct keys kept per table.
    public static let defaultNameLimit = 64

    public let nameLimit: Int

    /// Generator class name -> times it was reached with no evaluation of its
    /// own. These produce the skeleton reference pose.
    public private(set) var unevaluatedGenerators: [String: Int] = [:]
    public private(set) var unevaluatedGeneratorTotal = 0

    /// Generator class name -> times it was evaluated only as far as one child,
    /// with the rest of its semantics still owed. A `BSBoneSwitchGenerator`
    /// that runs its default generator and ignores its per-bone children is
    /// here, not in `unevaluatedGenerators`.
    public private(set) var partialGenerators: [String: Int] = [:]
    public private(set) var partialGeneratorTotal = 0

    /// Modifier class name -> times it passed its input through unmodified.
    public private(set) var passthroughModifiers: [String: Int] = [:]
    public private(set) var passthroughModifierTotal = 0

    /// Clip animation name -> times a clip generator could not find its clip.
    public private(set) var unresolvedClips: [String: Int] = [:]
    public private(set) var unresolvedClipTotal = 0

    /// Binding member path -> times a binding could not be applied, because the
    /// variable index was out of range, the member is not a bindable property
    /// of that class, or the binding addresses a character property and this
    /// instance has no character data.
    public private(set) var unappliedBindings: [String: Int] = [:]
    public private(set) var unappliedBindingTotal = 0

    /// Class name -> times a reference pointed at an object with no decoder, or
    /// at a location the packfile registers no class for.
    public private(set) var undecodableObjects: [String: Int] = [:]
    public private(set) var undecodableObjectTotal = 0

    /// Binding member path -> times a binding was resolved onto a node. Not a
    /// gap: this is the positive half of the binding ledger, and it is what
    /// says which member paths the vanilla graph actually drives.
    public private(set) var boundMemberPaths: [String: Int] = [:]
    public private(set) var boundMemberPathTotal = 0

    /// Named feature slug -> times the evaluator took a documented shortcut
    /// rather than the full semantics. Slugs are the `Gap` cases below, so the
    /// report reads as `transitionConditionUnresolved`, `clipPingPongAsLoop`,
    /// and so on.
    public private(set) var featureGaps: [String: Int] = [:]
    public private(set) var featureGapTotal = 0

    public private(set) var generatorsEvaluated = 0
    public private(set) var modifiersEvaluated = 0
    public private(set) var updatesRun = 0

    public init(nameLimit: Int = BehaviorTally.defaultNameLimit) {
        self.nameLimit = max(0, nameLimit)
    }

    /// A documented shortcut the evaluator takes. Each case is a worklist entry
    /// for a later issue, named in `docs/engine/behavior-runtime.md`.
    public enum Gap: String, Sendable {
        /// A state machine's start state could not be located by id.
        case stateMachineNoStartState
        /// A transition fired while another was still blending, and the older
        /// blend was dropped rather than nested inside the new one.
        case stateMachineTransitionInterrupted
        /// `m_randomTransitionEventId` fired and the destination was chosen by
        /// highest `m_probability` rather than at random, because an unseeded
        /// random source cannot be stepped deterministically.
        case stateMachineRandomTransitionFixed
        /// A transition's condition string did not fit the authored expression
        /// grammar, so the transition was blocked.
        case transitionConditionUnparsed
        /// A transition's condition named a variable this graph does not
        /// declare, so the transition was blocked.
        case transitionConditionUnresolved
        /// A transition named a `hkbTransitionEffect` that is not a
        /// `hkbBlendingTransitionEffect`, and was run as an instant cut.
        case transitionEffectUnevaluated
        /// A transition effect asked for a blend curve with no formula here,
        /// and was run as the smooth curve.
        case transitionBlendCurveApproximated
        /// `FLAG_DELAY_STATE_CHANGE` was set and the state change was made
        /// immediately anyway.
        case transitionStateChangeNotDelayed
        /// `m_fromNestedStateId` was marked valid and ignored.
        case transitionFromNestedStateIgnored
        /// A trigger or initiate interval carried a non-zero time bound, which
        /// is read as an event window only.
        case transitionTimeIntervalIgnored
        /// `m_toGeneratorStartTimeFraction` was non-zero and ignored.
        case transitionStartFractionIgnored
        /// A `BSSynchronizedClipGenerator` ran its clip without marker alignment, which
        /// needs a partner character.
        case synchronizedClipMarkerIgnored
        /// `hkbClipGenerator` ping-pong playback was run as a plain loop.
        case clipPingPongAsLoop
        /// `hkbClipGenerator` user-controlled playback was run from
        /// `m_userControlledTimeFraction` without an external driver.
        case clipUserControlled
        /// `hkbClipGenerator::ClipFlags` mirroring was ignored.
        case clipMirrored
        /// A clip carries an `hkaAnimatedReferenceFrame`, and its travel was
        /// approximated by differencing the root bone rather than by decoding
        /// that reference frame. No file in a vanilla install reaches this.
        case clipExtractedMotionApproximated
        /// A blender's cyclic or parametric blend flags were ignored and the
        /// authored child weights were used directly.
        case blenderParametricAsWeights
        /// A blender subtracted-last-child blend was run as an ordinary blend.
        case blenderSubtractLastChild
        /// `hkbPoseMatchingGenerator` was run as its blender base.
        case poseMatchingAsBlender
        /// A `hkbBehaviorReferenceGenerator` names a behavior file no source
        /// could supply (`BehaviorReferenceSource`).
        case unresolvedBehaviorReference
        /// A generator's `m_enable`-equivalent binding disabled it, which the
        /// evaluator honours by returning the reference pose.
        case disabledNode
        /// Recursion stopped at the depth cap, which means the graph is deeper
        /// than the cap or contains a generator cycle.
        case depthCapReached
    }

    // MARK: - Recording

    public mutating func noteUpdate() {
        updatesRun += 1
    }

    public mutating func noteGenerator() {
        generatorsEvaluated += 1
    }

    public mutating func noteModifier() {
        modifiersEvaluated += 1
    }

    public mutating func noteUnevaluatedGenerator(_ className: String) {
        unevaluatedGeneratorTotal += 1
        Self.bump(&unevaluatedGenerators, className, limit: nameLimit)
    }

    public mutating func notePartialGenerator(_ className: String) {
        partialGeneratorTotal += 1
        Self.bump(&partialGenerators, className, limit: nameLimit)
    }

    public mutating func notePassthroughModifier(_ className: String) {
        passthroughModifierTotal += 1
        Self.bump(&passthroughModifiers, className, limit: nameLimit)
    }

    public mutating func noteUnresolvedClip(_ animationName: String?) {
        unresolvedClipTotal += 1
        Self.bump(&unresolvedClips, animationName ?? "<unnamed>", limit: nameLimit)
    }

    public mutating func noteBinding(_ memberPath: String) {
        boundMemberPathTotal += 1
        Self.bump(&boundMemberPaths, memberPath, limit: nameLimit)
    }

    public mutating func noteUnappliedBinding(_ memberPath: String?) {
        unappliedBindingTotal += 1
        Self.bump(&unappliedBindings, memberPath ?? "<self>", limit: nameLimit)
    }

    public mutating func noteUndecodableObject(_ className: String?) {
        undecodableObjectTotal += 1
        Self.bump(&undecodableObjects, className ?? "<unregistered>", limit: nameLimit)
    }

    public mutating func note(_ gap: Gap) {
        featureGapTotal += 1
        Self.bump(&featureGaps, gap.rawValue, limit: nameLimit)
    }

    /// Adds one to `key`, refusing new keys past `limit` so a pathological
    /// graph cannot grow a table without bound. The totals above are bumped by
    /// the caller and keep counting either way. Static because passing a stored
    /// property `inout` to a method on `self` would be an overlapping access.
    private static func bump(_ table: inout [String: Int], _ key: String, limit: Int) {
        if table[key] != nil || table.count < limit {
            table[key, default: 0] += 1
        }
    }

    // MARK: - Reporting

    /// True when every generator and modifier the instance reached had real
    /// semantics behind it.
    public var isClean: Bool {
        gapTotal == 0
    }

    /// Every shortcut, miss, and pass-through, across all buckets.
    public var gapTotal: Int {
        unevaluatedGeneratorTotal + partialGeneratorTotal + passthroughModifierTotal
            + unresolvedClipTotal + unappliedBindingTotal + undecodableObjectTotal
            + featureGapTotal
    }

    public var rankedUnevaluatedGenerators: [(name: String, count: Int)] {
        Self.ranked(unevaluatedGenerators)
    }

    public var rankedPartialGenerators: [(name: String, count: Int)] {
        Self.ranked(partialGenerators)
    }

    public var rankedPassthroughModifiers: [(name: String, count: Int)] {
        Self.ranked(passthroughModifiers)
    }

    public var rankedUnresolvedClips: [(name: String, count: Int)] {
        Self.ranked(unresolvedClips)
    }

    public var rankedUnappliedBindings: [(name: String, count: Int)] {
        Self.ranked(unappliedBindings)
    }

    public var rankedUndecodableObjects: [(name: String, count: Int)] {
        Self.ranked(undecodableObjects)
    }

    public var rankedFeatureGaps: [(name: String, count: Int)] {
        Self.ranked(featureGaps)
    }

    public var rankedBoundMemberPaths: [(name: String, count: Int)] {
        Self.ranked(boundMemberPaths)
    }

    /// Merges another instance's tally into this one, so a probe over many
    /// graphs reports one ledger. Totals add; capped tables stay capped.
    public mutating func merge(_ other: BehaviorTally) {
        unevaluatedGeneratorTotal += other.unevaluatedGeneratorTotal
        partialGeneratorTotal += other.partialGeneratorTotal
        passthroughModifierTotal += other.passthroughModifierTotal
        unresolvedClipTotal += other.unresolvedClipTotal
        unappliedBindingTotal += other.unappliedBindingTotal
        undecodableObjectTotal += other.undecodableObjectTotal
        featureGapTotal += other.featureGapTotal
        boundMemberPathTotal += other.boundMemberPathTotal
        generatorsEvaluated += other.generatorsEvaluated
        modifiersEvaluated += other.modifiersEvaluated
        updatesRun += other.updatesRun
        let limit = nameLimit
        Self.merge(&unevaluatedGenerators, other.unevaluatedGenerators, limit: limit)
        Self.merge(&partialGenerators, other.partialGenerators, limit: limit)
        Self.merge(&passthroughModifiers, other.passthroughModifiers, limit: limit)
        Self.merge(&unresolvedClips, other.unresolvedClips, limit: limit)
        Self.merge(&unappliedBindings, other.unappliedBindings, limit: limit)
        Self.merge(&undecodableObjects, other.undecodableObjects, limit: limit)
        Self.merge(&featureGaps, other.featureGaps, limit: limit)
        Self.merge(&boundMemberPaths, other.boundMemberPaths, limit: limit)
    }

    /// Key order is sorted so a table that fills mid-merge keeps the same names
    /// whatever order the source dictionary happened to hash into.
    private static func merge(
        _ table: inout [String: Int],
        _ other: [String: Int],
        limit: Int
    ) {
        for (key, count) in other.sorted(by: { $0.key < $1.key }) {
            if table[key] != nil || table.count < limit {
                table[key, default: 0] += count
            }
        }
    }

    private static func ranked(_ table: [String: Int]) -> [(name: String, count: Int)] {
        table
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }
}
