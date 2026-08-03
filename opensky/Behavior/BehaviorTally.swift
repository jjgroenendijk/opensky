// What the behavior evaluator could not evaluate (issue #187).
//
// The evaluator never throws and never crashes: a node class it has no
// semantics for still returns a pose — its child's, or the skeleton reference
// pose — and costs one tally entry. That makes the tally a first-class result
// rather than a debug aid. It is the coverage evidence for "which Havok
// Behavior classes does OpenSky still owe Skyrim?", the same role
// `ConditionTally` plays for CTDA conditions and `AS2Tally` for ActionScript,
// and it is what the real-data probe reads and what the milestone gate (#191)
// reports.
//
// Every name table is capped so a pathological modded graph cannot grow the
// tally without bound, and every total keeps counting past its cap: a truncated
// table still reports how much it stopped naming.

import Foundation

/// Counts of everything one behavior graph instance could not evaluate, plus
/// the volume it did evaluate.
nonisolated struct BehaviorTally: Equatable, Sendable {
    /// Distinct keys kept per table.
    static let defaultNameLimit = 64

    let nameLimit: Int

    /// Generator class name -> times it was reached with no evaluation of its
    /// own. These produce the skeleton reference pose.
    private(set) var unevaluatedGenerators: [String: Int] = [:]
    private(set) var unevaluatedGeneratorTotal = 0

    /// Generator class name -> times it was evaluated only as far as one child,
    /// with the rest of its semantics still owed. A `BSBoneSwitchGenerator`
    /// that runs its default generator and ignores its per-bone children is
    /// here, not in `unevaluatedGenerators`.
    private(set) var partialGenerators: [String: Int] = [:]
    private(set) var partialGeneratorTotal = 0

    /// Modifier class name -> times it passed its input through unmodified.
    private(set) var passthroughModifiers: [String: Int] = [:]
    private(set) var passthroughModifierTotal = 0

    /// Clip animation name -> times a clip generator could not find its clip.
    private(set) var unresolvedClips: [String: Int] = [:]
    private(set) var unresolvedClipTotal = 0

    /// Binding member path -> times a binding could not be applied, because the
    /// variable index was out of range, the member is not a bindable property
    /// of that class, or the binding addresses a character property and this
    /// instance has no character data.
    private(set) var unappliedBindings: [String: Int] = [:]
    private(set) var unappliedBindingTotal = 0

    /// Class name -> times a reference pointed at an object with no decoder, or
    /// at a location the packfile registers no class for.
    private(set) var undecodableObjects: [String: Int] = [:]
    private(set) var undecodableObjectTotal = 0

    /// Binding member path -> times a binding was resolved onto a node. Not a
    /// gap: this is the positive half of the binding ledger, and it is what
    /// says which member paths the vanilla graph actually drives.
    private(set) var boundMemberPaths: [String: Int] = [:]
    private(set) var boundMemberPathTotal = 0

    /// Named feature slug -> times the evaluator took a documented shortcut
    /// rather than the full semantics. Slugs are the `Gap` cases below, so the
    /// report reads as `transitionConditionUnresolved`, `clipPingPongAsLoop`,
    /// and so on.
    private(set) var featureGaps: [String: Int] = [:]
    private(set) var featureGapTotal = 0

    private(set) var generatorsEvaluated = 0
    private(set) var modifiersEvaluated = 0
    private(set) var updatesRun = 0

    init(nameLimit: Int = BehaviorTally.defaultNameLimit) {
        self.nameLimit = max(0, nameLimit)
    }

    /// A documented shortcut the evaluator takes. Each case is a worklist entry
    /// for a later issue, named in `docs/engine/behavior-runtime.md`.
    enum Gap: String, Sendable {
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
        /// A `BSSynchronizedClipGenerator` ran its wrapped clip without the
        /// marker alignment, which needs the partner character item 14.5 adds.
        case synchronizedClipMarkerIgnored
        /// `hkbClipGenerator` ping-pong playback was run as a plain loop.
        case clipPingPongAsLoop
        /// `hkbClipGenerator` user-controlled playback was run from
        /// `m_userControlledTimeFraction` without an external driver.
        case clipUserControlled
        /// `hkbClipGenerator::ClipFlags` mirroring was ignored.
        case clipMirrored
        /// A blender's cyclic or parametric blend flags were ignored and the
        /// authored child weights were used directly.
        case blenderParametricAsWeights
        /// A blender subtracted-last-child blend was run as an ordinary blend.
        case blenderSubtractLastChild
        /// A blender child's per-bone weight mask was ignored.
        case blenderBoneWeights
        /// `hkbPoseMatchingGenerator` was run as its blender base.
        case poseMatchingAsBlender
        /// A `hkbBehaviorReferenceGenerator` names a behavior file this
        /// instance does not hold. Issue #190 resolves these.
        case unresolvedBehaviorReference
        /// A generator's `m_enable`-equivalent binding disabled it, which the
        /// evaluator honours by returning the reference pose.
        case disabledNode
        /// Recursion stopped at the depth cap, which means the graph is deeper
        /// than the cap or contains a generator cycle.
        case depthCapReached
    }

    // MARK: - Recording

    mutating func noteUpdate() {
        updatesRun += 1
    }

    mutating func noteGenerator() {
        generatorsEvaluated += 1
    }

    mutating func noteModifier() {
        modifiersEvaluated += 1
    }

    mutating func noteUnevaluatedGenerator(_ className: String) {
        unevaluatedGeneratorTotal += 1
        Self.bump(&unevaluatedGenerators, className, limit: nameLimit)
    }

    mutating func notePartialGenerator(_ className: String) {
        partialGeneratorTotal += 1
        Self.bump(&partialGenerators, className, limit: nameLimit)
    }

    mutating func notePassthroughModifier(_ className: String) {
        passthroughModifierTotal += 1
        Self.bump(&passthroughModifiers, className, limit: nameLimit)
    }

    mutating func noteUnresolvedClip(_ animationName: String?) {
        unresolvedClipTotal += 1
        Self.bump(&unresolvedClips, animationName ?? "<unnamed>", limit: nameLimit)
    }

    mutating func noteBinding(_ memberPath: String) {
        boundMemberPathTotal += 1
        Self.bump(&boundMemberPaths, memberPath, limit: nameLimit)
    }

    mutating func noteUnappliedBinding(_ memberPath: String?) {
        unappliedBindingTotal += 1
        Self.bump(&unappliedBindings, memberPath ?? "<self>", limit: nameLimit)
    }

    mutating func noteUndecodableObject(_ className: String?) {
        undecodableObjectTotal += 1
        Self.bump(&undecodableObjects, className ?? "<unregistered>", limit: nameLimit)
    }

    mutating func note(_ gap: Gap) {
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
    var isClean: Bool {
        gapTotal == 0
    }

    /// Every shortcut, miss, and pass-through, across all buckets.
    var gapTotal: Int {
        unevaluatedGeneratorTotal + partialGeneratorTotal + passthroughModifierTotal
            + unresolvedClipTotal + unappliedBindingTotal + undecodableObjectTotal
            + featureGapTotal
    }

    var rankedUnevaluatedGenerators: [(name: String, count: Int)] {
        Self.ranked(unevaluatedGenerators)
    }

    var rankedPartialGenerators: [(name: String, count: Int)] {
        Self.ranked(partialGenerators)
    }

    var rankedPassthroughModifiers: [(name: String, count: Int)] {
        Self.ranked(passthroughModifiers)
    }

    var rankedUnresolvedClips: [(name: String, count: Int)] {
        Self.ranked(unresolvedClips)
    }

    var rankedUnappliedBindings: [(name: String, count: Int)] {
        Self.ranked(unappliedBindings)
    }

    var rankedUndecodableObjects: [(name: String, count: Int)] {
        Self.ranked(undecodableObjects)
    }

    var rankedFeatureGaps: [(name: String, count: Int)] {
        Self.ranked(featureGaps)
    }

    var rankedBoundMemberPaths: [(name: String, count: Int)] {
        Self.ranked(boundMemberPaths)
    }

    /// Merges another instance's tally into this one, so a probe over many
    /// graphs reports one ledger. Totals add; capped tables stay capped.
    mutating func merge(_ other: BehaviorTally) {
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
