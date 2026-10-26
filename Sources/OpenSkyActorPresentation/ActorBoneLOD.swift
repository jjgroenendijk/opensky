// Bone levels of detail on an actor's rig: past a `BSBoneLODExtraData` distance, the
// named bone and every bone after it in the rig's order keep their last pose.
// The rule and its sources: docs/formats/nif-controllers.md#node-controller-rules.

import Foundation
import OpenSkyFormatsAnimation
import OpenSkyFormatsMesh

nonisolated public struct ActorBoneLOD: Equatable, Sendable {
    public struct Cutoff: Equatable, Sendable {
        public let distance: Float
        /// Index into the rig's bones.
        public let bone: Int
    }

    /// Nearest first.
    public let cutoffs: [Cutoff]

    /// Nil when no entry names a rig bone.
    public init?(bones: [NIFBoneLODLevels.Bone], rig: HKASkeleton) {
        var cutoffs: [Cutoff] = []
        for entry in bones {
            guard
                let name = entry.name,
                let bone = rig.boneNames.firstIndex(where: {
                    $0.caseInsensitiveCompare(name) == .orderedSame
                })
            else { continue }
            cutoffs.append(Cutoff(distance: entry.distance, bone: bone))
        }
        guard !cutoffs.isEmpty else { return nil }
        self.cutoffs = cutoffs.sorted { ($0.distance, $0.bone) < ($1.distance, $1.bone) }
    }

    /// The first rig bone that holds its pose at `distance`, or nil when every bone moves.
    public func firstHeldBone(atDistance distance: Float) -> Int? {
        cutoffs.filter { distance > $0.distance }.map(\.bone).min()
    }

    /// `next`, with every bone from `firstHeld` on taken from `previous`.
    public static func holding(
        _ next: [HKABonePose], previous: [HKABonePose], from firstHeld: Int?
    ) -> [HKABonePose] {
        guard let firstHeld, previous.count == next.count, firstHeld < next.count else {
            return next
        }
        return Array(next[..<firstHeld]) + previous[firstHeld...]
    }
}
