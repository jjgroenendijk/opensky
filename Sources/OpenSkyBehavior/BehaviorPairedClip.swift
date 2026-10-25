// A paired clip, such as `Paired_Mount.hkx`, animates two actors at once. Its tracks
// are named after the bones of both: the lead actor's plain, the other's with the
// `BSSynchronizedClipGenerator` sync prefix, such as `2_HorsePelvis`. Each actor plays
// only its own tracks, found by bone name (docs/engine/behavior-clips.md).

import Foundation
import OpenSkyFormatsAnimation

/// Which track of a paired clip poses which bone of one actor.
nonisolated public struct PairedTrackMap: Equatable, Sendable {
    /// Bone index by track index.
    public let bones: [Int: Int]

    /// Maps the tracks that belong to the actor with `prefix`. An empty prefix takes
    /// the tracks with no actor prefix: a prefix is digits and an underscore.
    public init(trackNames: [String?], prefix: String, boneNames: [String]) {
        var byName: [String: Int] = [:]
        for (index, name) in boneNames.enumerated() where byName[name] == nil {
            byName[name] = index
        }
        var bones: [Int: Int] = [:]
        for (track, name) in trackNames.enumerated() {
            guard
                let name,
                let bone = Self.boneName(of: name, prefix: prefix),
                let index = byName[bone]
            else { continue }
            bones[track] = index
        }
        self.bones = bones
    }

    /// The bone a track drives for the actor with `prefix`, or nil when the track
    /// belongs to the other actor.
    static func boneName(of track: String, prefix: String) -> String? {
        guard prefix.isEmpty else {
            return track.hasPrefix(prefix) ? String(track.dropFirst(prefix.count)) : nil
        }
        return hasActorPrefix(track) ? nil : track
    }

    private static func hasActorPrefix(_ track: String) -> Bool {
        let digits = track.prefix { $0.isASCII && $0.isNumber }
        return !digits.isEmpty && track.dropFirst(digits.count).first == "_"
    }
}

/// One actor's view of a paired clip: its own tracks on its own bones, and the
/// annotations of those tracks only.
nonisolated public struct PairedBehaviorClip: BehaviorClip {
    public let base: any BehaviorClip
    public let map: PairedTrackMap
    public let annotations: [HKAAnnotation]

    public init(_ base: any BehaviorClip, map: PairedTrackMap) {
        self.base = base
        self.map = map
        annotations = base.annotations(onTracks: Set(map.bones.keys))
    }

    public var duration: Float {
        base.duration
    }

    public var carriesExtractedMotion: Bool {
        base.carriesExtractedMotion
    }

    public var isAdditive: Bool {
        base.isAdditive
    }

    public func samples(at time: Float) -> [HKABoneTransformSample] {
        base.samples(at: time).compactMap { sample in
            map.bones[sample.boneIndex].map {
                HKABoneTransformSample(boneIndex: $0, pose: sample.pose)
            }
        }
    }
}
