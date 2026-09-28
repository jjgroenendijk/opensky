// The seam between `hkbClipGenerator` and a loaded animation (issue #187).
//
// A clip generator names its clip twice — as a string the character file's
// `m_animationNames` spells, and as an index into that same list — and says
// nothing about where the bytes are. Turning either into a sampled pose is
// somebody else's job: item 14.5 wires the character file, item 14.6 replaces
// the hardcoded `loadAnimationClip` path. So the evaluator asks for a clip
// through this protocol and does not care who answers.
//
// The engine-side answer wraps the sampling that already exists,
// `HKASplineCompressedAnimation.boneLocalTransforms(at:binding:)` resolved
// through `hkaAnimationBinding`. The test-side answer is a clip built in code.
// Neither is privileged, which is what lets the evaluator be unit-tested with
// no packfile and no install.

import Foundation

/// One loadable animation, as the evaluator needs it: how long it runs and what
/// the bones look like at a time inside it.
nonisolated protocol BehaviorClip {
    /// Clip length in seconds. Zero or less means the clip cannot be sampled,
    /// and a clip generator holding one produces the reference pose.
    var duration: Float { get }
    /// Local bone samples at `time` seconds from clip start, clamped into the
    /// clip by the implementation. Never throws: a sampling failure comes back
    /// as an empty sample list, which leaves every bone at the reference pose.
    func samples(at time: Float) -> [HKABoneTransformSample]
    /// True when the clip's own data says it carries authored travel
    /// (`hkaAnimation.m_extractedMotion`). False means the clip animates in
    /// place, and the evaluator reports no root motion for it at all rather
    /// than differencing a root bone that only jitters.
    var carriesExtractedMotion: Bool { get }
    /// The clip's own annotations, earliest first, in seconds from clip start.
    /// Each one names an event the evaluator raises as playback passes it —
    /// which is where Skyrim's `FootLeft` and `FootRight` come from, so a clip
    /// that drops these is silent underfoot (see HKAAnnotationTrack.swift).
    var annotations: [HKAAnnotation] { get }
}

nonisolated extension BehaviorClip {
    /// In place unless the clip says otherwise. A clip built in code carries no
    /// reference frame, and neither does any vanilla animation.
    var carriesExtractedMotion: Bool {
        false
    }

    /// Unannotated unless the clip says otherwise, so a test clip built in code
    /// stays a bone source and nothing else.
    var annotations: [HKAAnnotation] {
        []
    }
}

/// Where a clip generator's animation comes from. One instance is shared by
/// every clip generator of one graph instance.
nonisolated protocol BehaviorClipSource {
    /// The clip a generator names, or nil when this source cannot supply it.
    /// Both spellings are passed because vanilla data uses both: most
    /// generators carry a name, and a few carry only a binding index.
    func clip(named name: String?, bindingIndex: Int) -> (any BehaviorClip)?
}

/// A source that supplies nothing. The evaluator stays usable — every clip
/// generator falls back to the reference pose and costs one tally entry — which
/// is what the graph-shape unit tests and the structural half of the real-data
/// probe want.
nonisolated struct EmptyBehaviorClipSource: BehaviorClipSource {
    func clip(named _: String?, bindingIndex _: Int) -> (any BehaviorClip)? {
        nil
    }
}

/// A clip backed by a decoded spline animation and its binding: the adapter
/// over the sampling seam that already existed before this milestone.
nonisolated struct SplineBehaviorClip: BehaviorClip {
    let animation: HKASplineCompressedAnimation
    let binding: HKAAnimationBinding

    var duration: Float {
        animation.duration
    }

    var carriesExtractedMotion: Bool {
        animation.carriesExtractedMotion
    }

    var annotations: [HKAAnnotation] {
        animation.annotations
    }

    func samples(at time: Float) -> [HKABoneTransformSample] {
        guard animation.duration > 0, time.isFinite else { return [] }
        let clamped = min(max(time, 0), animation.duration)
        return (try? animation.boneLocalTransforms(at: clamped, binding: binding)) ?? []
    }
}

/// A source backed by an in-memory table, keyed by the animation name the
/// generator spells and by binding index. Callers that already resolved their
/// clips — the real-data probe, and eventually item 14.6's loader — hand one of
/// these to the instance.
nonisolated struct BehaviorClipTable: BehaviorClipSource {
    private let byName: [String: any BehaviorClip]
    private let byIndex: [Int: any BehaviorClip]

    init(
        byName: [String: any BehaviorClip] = [:],
        byIndex: [Int: any BehaviorClip] = [:]
    ) {
        self.byName = byName
        self.byIndex = byIndex
    }

    /// Name lookup wins over index lookup, because a name survives a character
    /// file whose animation list a mod reordered.
    func clip(named name: String?, bindingIndex: Int) -> (any BehaviorClip)? {
        if let name, let clip = byName[Self.key(name)] {
            return clip
        }
        return byIndex[bindingIndex]
    }

    /// Animation names are compared case-insensitively on normalized
    /// separators, because Bethesda's authored names and the archive paths that
    /// carry them disagree on both.
    static func key(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "\\").lowercased()
    }
}
