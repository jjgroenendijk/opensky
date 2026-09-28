// Name-map from hkaSkeleton bones (todo 6.2) onto the NIF skeleton NiNode
// names bind-pose skinning already keys on (NIFSkeleton.boneTransforms). The
// two skeletons describe the same rig but are not identical sets: the HKX rig
// carries control + weapon-attach helper nodes with no mesh geometry, and the
// NIF carries nodes the animation rig omits. The map is partial by design;
// every unmatched bone is reported with a reason tag, never dropped silently
// (AGENTS.md reverse-engineering discipline). Pure name logic — no file I/O,
// unit-tested without real data. Observed vanilla human rig: 93 of 99 bones
// exact-match, 6 HKX-only helper nodes, 6 NIF-only nodes
// (docs/formats/hka-skeleton.md).

import Foundation

/// One HKX bone with no NIF node, or one NIF node with no HKX bone, plus the
/// reason it went unmatched.
nonisolated struct SkeletonBoneMismatch: Equatable {
    let name: String
    let reason: String
}

/// Result of matching HKX bone names against NIF node names, both directions.
/// Match is exact name equality — the vanilla rig shares bone names verbatim
/// between the two files, so no normalization is applied (it would mask real
/// divergence).
nonisolated struct SkeletonBoneMap {
    /// HKX bone names that also name a NIF node, in HKX bone order.
    let matched: [String]
    /// HKX bones with no NIF node (control/attach helpers, rig-only bones).
    let unmatchedHKX: [SkeletonBoneMismatch]
    /// NIF nodes with no HKX bone (mesh-only nodes the rig omits).
    let unmatchedNIF: [SkeletonBoneMismatch]

    var matchedCount: Int {
        matched.count
    }

    /// Builds the map. `nifNodeNames` is the NIF-side key set
    /// (NIFSkeleton.boneTransforms.keys).
    init(hkxBoneNames: [String], nifNodeNames: Set<String>) {
        var matched: [String] = []
        var unmatchedHKX: [SkeletonBoneMismatch] = []
        for bone in hkxBoneNames {
            if nifNodeNames.contains(bone) {
                matched.append(bone)
            } else {
                unmatchedHKX.append(SkeletonBoneMismatch(
                    name: bone,
                    reason: "no NIF node (HKX-only: control/attach helper or rig-only bone)"
                ))
            }
        }
        let hkxSet = Set(hkxBoneNames)
        self.matched = matched
        self.unmatchedHKX = unmatchedHKX
        unmatchedNIF = nifNodeNames.subtracting(hkxSet)
            .sorted()
            .map { SkeletonBoneMismatch(name: $0, reason: "no HKX bone (NIF-only node)") }
    }
}
